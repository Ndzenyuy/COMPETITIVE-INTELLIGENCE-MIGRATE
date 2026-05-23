"""
RAG (Retrieval-Augmented Generation) module.

Embeddings: Convert insights into vectors for semantic search.
Retrieval: Find similar past insights before new analysis.
Injection: Prepend relevant context to Claude's prompt.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sentence_transformers import SentenceTransformer
import chromadb
import json
from db.client import query_insights

# Initialize local embedding model
# all-MiniLM-L6-v2: lightweight (22MB), fast, 384-dim vectors
model = SentenceTransformer('all-MiniLM-L6-v2', device='cpu')

# Initialize Chroma client with new API (v0.4+)
# Uses local persistent storage in ./chroma_data/
chroma_client = chromadb.PersistentClient(path=os.getenv("CHROMA_PATH", "./chroma_data"))

# Get or create collection for insights
collection = chroma_client.get_or_create_collection(
    name="insights",
    metadata={"hnsw:space": "cosine"}
)

def _format_insight_text(insight):
    """
    Format a database insight row into searchable text.
    
    Args:
        insight: dict — one row from insights table
    
    Returns:
        str — formatted text for embedding
    """
    return f"{insight['competitor']} {insight['signal_type']}: {insight['title']}. {insight['description']}"

def store_insight_embedding(insight_id, competitor, signal_type, title, description):
    """
    Embed a single insight and store it in Chroma.
    
    Args:
        insight_id: int — database ID
        competitor: str — e.g., "Stripe"
        signal_type: str — e.g., "feature_launch"
        title: str — short headline
        description: str — longer text
    
    Returns:
        dict — the stored embedding metadata
    """
    # Format the text
    text = f"{competitor} {signal_type}: {title}. {description}"
    
    # Embed it
    embedding = model.encode(text).tolist()
    
    # Store in Chroma
    collection.add(
        ids=[str(insight_id)],
        embeddings=[embedding],
        documents=[text],
        metadatas=[{
            "competitor": competitor,
            "signal_type": signal_type,
            "title": title,
            "insight_id": str(insight_id)
        }]
    )
    
    return {"insight_id": insight_id, "stored": True}

def retrieve_similar(query_text, competitor=None, k=5):
    """
    Retrieve the k most similar past insights for a query.
    
    Args:
        query_text: str — e.g., "Stripe AI foundation model"
        competitor: str or None — filter by competitor (optional)
        k: int — how many results to return
    
    Returns:
        list of dicts — similar insights with distance scores
    """
    # Embed the query
    query_embedding = model.encode(query_text).tolist()
    
    # Search Chroma
    where_filter = {"competitor": competitor} if competitor else None
    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=k,
        where=where_filter
    )
    
    # Format results
    similar = []
    if results and results['ids'] and len(results['ids']) > 0:
        for i, insight_id in enumerate(results['ids'][0]):
            similar.append({
                "insight_id": int(insight_id),
                "text": results['documents'][0][i],
                "distance": results['distances'][0][i],  # 0 = identical, 1 = opposite
                "metadata": results['metadatas'][0][i]
            })
    
    return similar

def batch_embed_existing_insights():
    """
    Embed all insights currently in the database.
    Call this once after Phase 2 to populate the vector DB.
    
    Returns:
        dict — summary of what was embedded
    """
    # Fetch all insights from DB
    conn_insights = query_insights(limit=1000)
    
    if not conn_insights:
        print("No insights found in database")
        return {"embedded": 0}
    
    print(f"Embedding {len(conn_insights)} insights...")
    
    # Batch encode all texts
    texts = [_format_insight_text(insight) for insight in conn_insights]
    embeddings = model.encode(texts, show_progress_bar=True)
    
    # Add to Chroma in batch
    ids = [str(insight['id']) for insight in conn_insights]
    metadatas = [
        {
            "competitor": insight['competitor'],
            "signal_type": insight['signal_type'],
            "title": insight['title'],
            "insight_id": str(insight['id'])
        }
        for insight in conn_insights
    ]
    
    collection.add(
        ids=ids,
        embeddings=embeddings.tolist(),
        documents=texts,
        metadatas=metadatas
    )
    
    print(f"✓ Embedded {len(conn_insights)} insights")
    return {"embedded": len(conn_insights)}

def format_retrieval_context(similar_insights, max_insights=5):
    """
    Format retrieved insights into a readable context block for Claude.
    
    Args:
        similar_insights: list — output from retrieve_similar()
        max_insights: int — how many to include
    
    Returns:
        str — formatted markdown for injection into system prompt
    """
    if not similar_insights:
        return ""
    
    context = "## Past Insights (for reference, avoid re-extracting these):\n\n"
    
    for insight in similar_insights[:max_insights]:
        meta = insight['metadata']
        context += f"- **{meta['competitor']} ({meta['signal_type']})**: {meta['title']}\n"
    
    return context

if __name__ == "__main__":
    # Test: embed all existing insights
    print("Batch embedding all insights in the database...")
    result = batch_embed_existing_insights()
    print(json.dumps(result, indent=2))
    
    # Test: retrieve similar
    print("\nTesting retrieval...")
    similar = retrieve_similar("Stripe AI partnership", competitor="Stripe", k=3)
    print(f"Found {len(similar)} similar insights:")
    for s in similar:
        print(f"  - {s['metadata']['title']} (distance: {s['distance']:.3f})")