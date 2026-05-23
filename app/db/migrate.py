import os
import psycopg2

schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
with open(schema_path) as f:
    schema = f.read()

conn = psycopg2.connect(os.environ["DATABASE_URL"])
conn.autocommit = True
with conn.cursor() as cur:
    cur.execute(schema)
conn.close()

print("Schema applied successfully")
