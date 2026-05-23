CREATE TABLE IF NOT EXISTS insights (
  id SERIAL PRIMARY KEY,
  competitor TEXT NOT NULL,
  signal_type TEXT NOT NULL,  -- e.g., 'pricing', 'feature_launch', 'partnership', 'sentiment'
  title TEXT NOT NULL,
  description TEXT,
  source_url TEXT,
  confidence FLOAT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_competitor ON insights(competitor);
CREATE INDEX IF NOT EXISTS idx_signal_type ON insights(signal_type);
CREATE INDEX IF NOT EXISTS idx_created_at ON insights(created_at DESC);