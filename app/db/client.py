import psycopg2
from psycopg2.extras import RealDictCursor
import os

# Read connection string from environment
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:admin123@localhost:5432/competitive_intelligence")

def get_connection():
    """Open a connection to Postgres."""
    return psycopg2.connect(DATABASE_URL)

def save_insight(competitor, signal_type, title, description, source_url, confidence):
    """
    Save a single insight to the database.
    
    Args:
        competitor: str — competitor name (e.g., 'Stripe', 'PayPal')
        signal_type: str — type of signal ('pricing', 'feature_launch', etc.)
        title: str — short headline
        description: str — longer explanation
        source_url: str — where we found it
        confidence: float — 0.0 to 1.0, how sure we are
    
    Returns:
        int — the new insight's ID
    """
    conn = get_connection()
    cur = conn.cursor()
    
    cur.execute(
        """
        INSERT INTO insights (competitor, signal_type, title, description, source_url, confidence)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (competitor, signal_type, title, description, source_url, confidence)
    )
    
    insight_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    
    return insight_id

def query_insights(competitor=None, limit=10):
    """
    Fetch recent insights, optionally filtered by competitor.
    
    Args:
        competitor: str or None — filter by competitor name
        limit: int — how many rows to return
    
    Returns:
        list of dicts — each dict is one insight row
    """
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    if competitor:
        cur.execute(
            "SELECT * FROM insights WHERE competitor = %s ORDER BY created_at DESC LIMIT %s;",
            (competitor, limit)
        )
    else:
        cur.execute(
            "SELECT * FROM insights ORDER BY created_at DESC LIMIT %s;",
            (limit,)
        )
    
    rows = cur.fetchall()
    cur.close()
    conn.close()
    
    return rows