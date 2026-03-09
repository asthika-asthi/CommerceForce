GRANT ALL PRIVILEGES ON DATABASE commerceforcedatabase TO appuser;


-- Grant on schema
GRANT ALL ON SCHEMA public TO appuser;


-- Grant on all existing tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;


-- Grant on all existing sequences (covers all SERIAL columns)
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO appuser;


-- Grant on all existing functions (covers gen_random_uuid())
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO appuser;


-- Cover all future objects created after this point
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO appuser;


ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO appuser;


ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO appuser;

