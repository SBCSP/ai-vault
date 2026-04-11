// AI VaultIO — Rust bridge (flutter_rust_bridge v2)
// Provides high-performance vector storage and ANN search via LanceDB.
//
// Public async functions here are automatically picked up by FRB codegen.
// Run:  dart run flutter_rust_bridge_codegen generate
//
// Schema stored in LanceDB (Apache Arrow columnar):
//   source_id    Utf8          — original item UUID (or "wiki:path", "audit:id")
//   source_type  Utf8          — vault_entry | note | idea | document_chunk |
//                                chat_session | wiki_page | audit_log
//   model_name   Utf8          — embedding model (e.g. nomic-embed-text:latest)
//   content_hash Utf8          — SHA-256 of source text (skip re-index if same)
//   vector       FixedSizeList<f32>[dim] — the embedding
//   created_at   Int64         — Unix ms timestamp

use std::sync::Arc;

use anyhow::{anyhow, Result};
use arrow_array::{
    cast::AsArray, types::Float32Type, FixedSizeListArray, Float32Array,
    Int64Array, RecordBatch, RecordBatchIterator, StringArray,
};
use arrow_schema::{DataType, Field, Schema};
use futures::StreamExt;
use lancedb::{
    query::{ExecutableQuery, QueryBase, Select},
    Connection,
};
use once_cell::sync::OnceCell;
use tokio::sync::Mutex;

// ─── Exported types ──────────────────────────────────────────────────────────
// FRB generates matching Dart classes for these structs.

pub struct SimilarityResult {
    pub source_id: String,
    pub source_type: String,
    /// Cosine similarity in [-1, 1].  LanceDB _distance = 1 - cosine_sim.
    pub similarity: f64,
    pub content_hash: String,
    pub model_name: String,
}

pub struct SourceHashEntry {
    pub source_id: String,
    pub source_type: String,
    pub content_hash: String,
    pub model_name: String,
}

pub struct VectorDbStats {
    pub total_embeddings: i64,
    pub has_index: bool,
    pub db_path: String,
    pub embedding_dim: i32,
}

// ─── Global state ────────────────────────────────────────────────────────────

static STATE: OnceCell<Arc<Mutex<Option<LanceConfig>>>> = OnceCell::new();

fn global() -> Arc<Mutex<Option<LanceConfig>>> {
    STATE.get_or_init(|| Arc::new(Mutex::new(None))).clone()
}

/// Cheap-to-clone config held behind a Mutex.
/// We clone it out of the lock before doing async I/O so we never hold
/// the Mutex across an await point.
#[derive(Clone)]
struct LanceConfig {
    conn: Arc<Connection>, // Arc makes this cheaply cloneable
    embedding_dim: i32,
    db_path: String,
    has_index: bool,
}

/// Grab a clone of the config (drops the lock immediately).
async fn get_config() -> Result<LanceConfig> {
    let g = global();
    let lock = g.lock().await;
    lock.as_ref()
        .cloned()
        .ok_or_else(|| anyhow!("LanceDB not initialised — call initLanceDb first"))
}

// ─── Schema helpers ──────────────────────────────────────────────────────────

fn make_schema(dim: i32) -> Arc<Schema> {
    Arc::new(Schema::new(vec![
        Field::new("source_id", DataType::Utf8, false),
        Field::new("source_type", DataType::Utf8, false),
        Field::new("model_name", DataType::Utf8, false),
        Field::new("content_hash", DataType::Utf8, false),
        Field::new(
            "vector",
            DataType::FixedSizeList(
                Arc::new(Field::new("item", DataType::Float32, true)),
                dim,
            ),
            false,
        ),
        Field::new("created_at", DataType::Int64, false),
    ]))
}

/// Create the `embeddings` table if it doesn't exist yet.
async fn ensure_table(conn: &Connection, dim: i32) -> Result<()> {
    let names = conn.table_names().execute().await?;
    if !names.contains(&"embeddings".to_string()) {
        let schema = make_schema(dim);
        let empty: Vec<Result<RecordBatch, arrow_schema::ArrowError>> = vec![];
        conn.create_table(
            "embeddings",
            RecordBatchIterator::new(empty.into_iter(), schema),
        )
        .execute()
        .await?;
    }
    Ok(())
}

fn escape_sql(s: &str) -> String {
    s.replace('\'', "''")
}

/// Build a single-row RecordBatch for upsert.
fn make_batch(
    source_id: &str,
    source_type: &str,
    model_name: &str,
    content_hash: &str,
    vector: Vec<f32>,
    dim: i32,
) -> Result<RecordBatch> {
    if vector.len() as i32 != dim {
        return Err(anyhow!(
            "Vector dim mismatch: expected {}, got {}",
            dim,
            vector.len()
        ));
    }

    let schema = make_schema(dim);

    let float_arr = Arc::new(Float32Array::from(vector));
    let vector_col = Arc::new(FixedSizeListArray::try_new(
        Arc::new(Field::new("item", DataType::Float32, true)),
        dim,
        float_arr,
        None,
    )?);

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    Ok(RecordBatch::try_new(
        schema,
        vec![
            Arc::new(StringArray::from(vec![source_id])) as _,
            Arc::new(StringArray::from(vec![source_type])) as _,
            Arc::new(StringArray::from(vec![model_name])) as _,
            Arc::new(StringArray::from(vec![content_hash])) as _,
            vector_col as _,
            Arc::new(Int64Array::from(vec![now_ms])) as _,
        ],
    )?)
}

// ─── Public API ──────────────────────────────────────────────────────────────

/// Initialise LanceDB at `db_path`.  Must be called once at app startup.
/// `embedding_dim` must match the model (nomic-embed-text → 768).
pub async fn init_lance_db(db_path: String, embedding_dim: i32) -> Result<()> {
    let conn = lancedb::connect(&db_path).execute().await?;
    ensure_table(&conn, embedding_dim).await?;

    let config = LanceConfig {
        conn: Arc::new(conn),
        embedding_dim,
        db_path,
        has_index: false,
    };

    *global().lock().await = Some(config);
    Ok(())
}

/// Insert or replace a single embedding.
/// Delete-then-insert is LanceDB's upsert pattern.
pub async fn lance_upsert_embedding(
    source_id: String,
    source_type: String,
    model_name: String,
    content_hash: String,
    vector: Vec<f32>,
) -> Result<()> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;

    // Remove any existing row for this source
    table
        .delete(&format!("source_id = '{}'", escape_sql(&source_id)))
        .await?;

    // Insert new row
    let batch = make_batch(
        &source_id,
        &source_type,
        &model_name,
        &content_hash,
        vector,
        cfg.embedding_dim,
    )?;
    let schema = batch.schema();
    table
        .add(RecordBatchIterator::new(
            vec![Ok(batch)].into_iter(),
            schema,
        ))
        .execute()
        .await?;

    Ok(())
}

/// Remove the embedding for a given source item.
pub async fn lance_delete_by_source(source_id: String) -> Result<()> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;
    table
        .delete(&format!("source_id = '{}'", escape_sql(&source_id)))
        .await?;
    Ok(())
}

/// Return content_hash + model_name for a source item so the Dart side can
/// decide whether re-indexing is needed.
pub async fn lance_get_source_hash(source_id: String) -> Result<Option<SourceHashEntry>> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;

    let mut stream = table
        .query()
        .only_if(format!("source_id = '{}'", escape_sql(&source_id)))
        .select(Select::columns(&[
            "source_id",
            "source_type",
            "content_hash",
            "model_name",
        ]))
        .limit(1)
        .execute()
        .await?;

    while let Some(batch) = stream.next().await {
        let batch = batch?;
        if batch.num_rows() == 0 {
            break;
        }
        let sid = batch
            .column_by_name("source_id")
            .unwrap()
            .as_string::<i32>()
            .value(0)
            .to_string();
        let stype = batch
            .column_by_name("source_type")
            .unwrap()
            .as_string::<i32>()
            .value(0)
            .to_string();
        let hash = batch
            .column_by_name("content_hash")
            .unwrap()
            .as_string::<i32>()
            .value(0)
            .to_string();
        let model = batch
            .column_by_name("model_name")
            .unwrap()
            .as_string::<i32>()
            .value(0)
            .to_string();
        return Ok(Some(SourceHashEntry {
            source_id: sid,
            source_type: stype,
            content_hash: hash,
            model_name: model,
        }));
    }
    Ok(None)
}

/// ANN vector search using cosine distance.
/// Returns up to `top_k` results sorted by similarity descending.
/// `filter_types` restricts to those source_type values (empty = all types).
pub async fn lance_search_similar(
    query_vector: Vec<f32>,
    top_k: i32,
    filter_types: Vec<String>,
) -> Result<Vec<SimilarityResult>> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;

    // Build query — cosine distance so _distance = 1 - cosine_similarity
    let mut q = table
        .query()
        .nearest_to(query_vector)
        .map_err(|e| anyhow!("Invalid query vector: {e}"))?
        .distance_type(lancedb::DistanceType::Cosine)
        .limit(top_k as usize);

    if !filter_types.is_empty() {
        let types_sql = filter_types
            .iter()
            .map(|t| format!("'{}'", escape_sql(t)))
            .collect::<Vec<_>>()
            .join(", ");
        q = q.only_if(format!("source_type IN ({types_sql})"));
    }

    let mut stream = q.execute().await?;
    let mut results = Vec::new();

    while let Some(batch) = stream.next().await {
        let batch = batch?;
        let source_ids = batch
            .column_by_name("source_id")
            .unwrap()
            .as_string::<i32>();
        let source_types = batch
            .column_by_name("source_type")
            .unwrap()
            .as_string::<i32>();
        let content_hashes = batch
            .column_by_name("content_hash")
            .unwrap()
            .as_string::<i32>();
        let model_names = batch
            .column_by_name("model_name")
            .unwrap()
            .as_string::<i32>();
        let distances = batch
            .column_by_name("_distance")
            .unwrap()
            .as_primitive::<Float32Type>();

        for i in 0..batch.num_rows() {
            let distance = distances.value(i) as f64;
            results.push(SimilarityResult {
                source_id: source_ids.value(i).to_string(),
                source_type: source_types.value(i).to_string(),
                similarity: 1.0 - distance, // cosine similarity
                content_hash: content_hashes.value(i).to_string(),
                model_name: model_names.value(i).to_string(),
            });
        }
    }

    Ok(results)
}

/// Return (source_id, source_type, content_hash, model_name) for all rows,
/// optionally filtered to one source_type.  Used for batch change-detection.
pub async fn lance_get_all_hashes(source_type_filter: String) -> Result<Vec<SourceHashEntry>> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;

    let mut q = table.query().select(Select::columns(&[
        "source_id",
        "source_type",
        "content_hash",
        "model_name",
    ]));

    if !source_type_filter.is_empty() {
        q = q.only_if(format!(
            "source_type = '{}'",
            escape_sql(&source_type_filter)
        ));
    }

    let mut stream = q.execute().await?;
    let mut results = Vec::new();

    while let Some(batch) = stream.next().await {
        let batch = batch?;
        let source_ids = batch
            .column_by_name("source_id")
            .unwrap()
            .as_string::<i32>();
        let source_types = batch
            .column_by_name("source_type")
            .unwrap()
            .as_string::<i32>();
        let hashes = batch
            .column_by_name("content_hash")
            .unwrap()
            .as_string::<i32>();
        let models = batch
            .column_by_name("model_name")
            .unwrap()
            .as_string::<i32>();

        for i in 0..batch.num_rows() {
            results.push(SourceHashEntry {
                source_id: source_ids.value(i).to_string(),
                source_type: source_types.value(i).to_string(),
                content_hash: hashes.value(i).to_string(),
                model_name: models.value(i).to_string(),
            });
        }
    }

    Ok(results)
}

/// Stats for the VectorDB settings screen.
pub async fn lance_get_stats() -> Result<VectorDbStats> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;
    let total = table.count_rows(None).await? as i64;
    Ok(VectorDbStats {
        total_embeddings: total,
        has_index: cfg.has_index,
        db_path: cfg.db_path,
        embedding_dim: cfg.embedding_dim,
    })
}

/// Build an IVF-PQ HNSW index on the vector column.
/// Requires ≥ 256 rows.  Dramatically speeds up ANN search at scale.
pub async fn lance_create_vector_index() -> Result<()> {
    let cfg = get_config().await?;
    let table = cfg.conn.open_table("embeddings").execute().await?;

    let count = table.count_rows(None).await?;
    if count < 256 {
        return Err(anyhow!(
            "Need at least 256 embeddings to build a vector index (have {count})."
        ));
    }

    table
        .create_index(&["vector"], lancedb::index::Index::Auto)
        .execute()
        .await?;

    // Persist the flag in global state
    if let Some(ref mut config) = *global().lock().await {
        config.has_index = true;
    }

    Ok(())
}

/// Drop and recreate the embeddings table (complete wipe).
pub async fn lance_delete_all() -> Result<()> {
    let cfg = get_config().await?;
    cfg.conn.drop_table("embeddings").await?;
    ensure_table(&cfg.conn, cfg.embedding_dim).await?;

    if let Some(ref mut config) = *global().lock().await {
        config.has_index = false;
    }
    Ok(())
}

/// Returns true if init_lance_db has been called successfully.
pub fn lance_is_initialized() -> bool {
    global()
        .try_lock()
        .map(|g| g.is_some())
        .unwrap_or(false)
}
