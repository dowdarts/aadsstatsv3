-- =====================================================
--  CLEANUP: Drop existing objects if they exist
-- =====================================================

DROP VIEW IF EXISTS head_to_head_stats CASCADE;
DROP FUNCTION IF EXISTS calculate_group_standings(INTEGER, VARCHAR) CASCADE;
DROP TRIGGER IF EXISTS trigger_create_next_series ON series CASCADE;
DROP FUNCTION IF EXISTS create_next_series() CASCADE;
DROP TABLE IF EXISTS edit_log CASCADE;
DROP TABLE IF EXISTS match_stats CASCADE;
DROP TABLE IF EXISTS matches CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS series CASCADE;

-- Atlantic Amateur Darts Series (AADS) Database Schema
-- Full-featured statistics tracking system with multi-series support

-- =====================================================
-- 1. SERIES TABLE
-- =====================================================
CREATE TABLE series (
    id SERIAL PRIMARY KEY,
    series_name VARCHAR(50) NOT NULL,
    start_year INTEGER NOT NULL,
    is_complete BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- 2. PLAYERS TABLE
-- =====================================================
CREATE TABLE players (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    hometown VARCHAR(100),
    photo_url TEXT,
    bio TEXT,
    date_added TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- 3. EVENTS TABLE
-- =====================================================
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    series_id INTEGER REFERENCES series(id) ON DELETE CASCADE,
    event_number INTEGER NOT NULL CHECK (event_number BETWEEN 1 AND 7),
    event_name VARCHAR(100) NOT NULL,
    event_date DATE,
    winner_id INTEGER REFERENCES players(id),
    is_toc BOOLEAN DEFAULT FALSE,
    group_a_complete BOOLEAN DEFAULT FALSE,
    group_b_complete BOOLEAN DEFAULT FALSE,
    knockout_complete BOOLEAN DEFAULT FALSE,
    UNIQUE(series_id, event_number)
);

-- =====================================================
-- 4. MATCHES TABLE
-- =====================================================
CREATE TABLE matches (
    id SERIAL PRIMARY KEY,
    event_id INTEGER REFERENCES events(id) ON DELETE CASCADE,
    stage VARCHAR(20) NOT NULL, -- 'GROUP_A', 'GROUP_B', 'QF1', 'QF2', 'QF3', 'QF4', 'SF1', 'SF2', 'FINAL'
    match_label VARCHAR(50), -- e.g., 'QF1: A1 vs B4'
    player_1_id INTEGER REFERENCES players(id),
    player_2_id INTEGER REFERENCES players(id),
    p1_legs INTEGER DEFAULT 0,
    p2_legs INTEGER DEFAULT 0,
    p1_sets INTEGER DEFAULT 0,
    p2_sets INTEGER DEFAULT 0,
    winner_id INTEGER REFERENCES players(id),
    match_date TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- 5. MATCH_STATS TABLE
-- =====================================================
CREATE TABLE match_stats (
    id SERIAL PRIMARY KEY,
    match_id INTEGER REFERENCES matches(id) ON DELETE CASCADE,
    player_id INTEGER REFERENCES players(id),
    three_dart_avg DECIMAL(5,2),
    first_nine_avg DECIMAL(5,2),
    checkout_completed INTEGER DEFAULT 0,
    checkout_opportunity INTEGER DEFAULT 0,
    tons_110_plus INTEGER DEFAULT 0,
    tons_120_plus INTEGER DEFAULT 0,
    tons_140_plus INTEGER DEFAULT 0,
    tons_160_plus INTEGER DEFAULT 0,
    one_eighties INTEGER DEFAULT 0,
    UNIQUE(match_id, player_id)
);

-- =====================================================
-- 6. EDIT_LOG TABLE (Auto-cleaned after 3 months)
-- =====================================================
CREATE TABLE edit_log (
    id SERIAL PRIMARY KEY,
    series_id INTEGER REFERENCES series(id) ON DELETE CASCADE,
    event_id INTEGER REFERENCES events(id) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    admin_action VARCHAR(50) NOT NULL, -- 'created', 'updated', 'reopened'
    stage_affected VARCHAR(50), -- 'GROUP_A', 'GROUP_B', 'KNOCKOUT'
    changes_description TEXT
);

-- =====================================================
-- 7. SUPABASE STORAGE BUCKET SETUP
-- =====================================================
-- Run this in Supabase SQL Editor after schema creation:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('player-photos', 'player-photos', true);

-- =====================================================
-- 8. AUTO-CLEANUP CRON JOB FOR EDIT LOGS
-- =====================================================
-- Delete edit logs older than 3 months
-- Enable pg_cron extension in Supabase dashboard first
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
    'cleanup-old-edit-logs',
    '0 2 * * *', -- Run daily at 2 AM
    $$DELETE FROM edit_log WHERE timestamp < NOW() - INTERVAL '3 months'$$
);

-- =====================================================
-- 9. TRIGGER: AUTO-CREATE NEXT SERIES ON COMPLETION
-- =====================================================
CREATE OR REPLACE FUNCTION create_next_series()
RETURNS TRIGGER AS $$
DECLARE
    current_series_num INTEGER;
    next_series_num INTEGER;
BEGIN
    -- Check if Event 7 (TOC) knockout is complete
    IF NEW.event_number = 7 AND NEW.is_toc = TRUE AND NEW.knockout_complete = TRUE THEN
        -- Mark series as complete
        UPDATE series SET is_complete = TRUE WHERE id = NEW.series_id;
        
        -- Get current series number
        SELECT CAST(SUBSTRING(series_name FROM '[0-9]+') AS INTEGER) INTO current_series_num
        FROM series WHERE id = NEW.series_id;
        
        next_series_num := current_series_num + 1;
        
        -- Create next series if it doesn't exist
        INSERT INTO series (series_name, start_year, is_complete)
        VALUES ('Series ' || next_series_num, EXTRACT(YEAR FROM NOW()), FALSE)
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_next_series
AFTER UPDATE ON events
FOR EACH ROW
EXECUTE FUNCTION create_next_series();

-- =====================================================
-- 10. VIEW: HEAD-TO-HEAD STATS
-- =====================================================
CREATE OR REPLACE VIEW head_to_head_stats AS
SELECT 
    LEAST(m.player_1_id, m.player_2_id) AS player_a_id,
    GREATEST(m.player_1_id, m.player_2_id) AS player_b_id,
    COUNT(*) AS total_matches,
    SUM(CASE WHEN m.winner_id = LEAST(m.player_1_id, m.player_2_id) THEN 1 ELSE 0 END) AS player_a_wins,
    SUM(CASE WHEN m.winner_id = GREATEST(m.player_1_id, m.player_2_id) THEN 1 ELSE 0 END) AS player_b_wins,
    SUM(CASE WHEN m.player_1_id = LEAST(m.player_1_id, m.player_2_id) THEN m.p1_legs ELSE m.p2_legs END) AS player_a_legs_won,
    SUM(CASE WHEN m.player_1_id = LEAST(m.player_1_id, m.player_2_id) THEN m.p2_legs ELSE m.p1_legs END) AS player_b_legs_won,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = LEAST(m.player_1_id, m.player_2_id) THEN ms.three_dart_avg END) AS numeric), 2) AS player_a_avg_3da,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = GREATEST(m.player_1_id, m.player_2_id) THEN ms.three_dart_avg END) AS numeric), 2) AS player_b_avg_3da,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = LEAST(m.player_1_id, m.player_2_id) THEN ms.first_nine_avg END) AS numeric), 2) AS player_a_first9_avg,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = GREATEST(m.player_1_id, m.player_2_id) THEN ms.first_nine_avg END) AS numeric), 2) AS player_b_first9_avg,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = LEAST(m.player_1_id, m.player_2_id) THEN (ms.checkout_completed::FLOAT / NULLIF(ms.checkout_opportunity, 0) * 100) END) AS numeric), 2) AS player_a_co_percent,
    ROUND(CAST(AVG(CASE WHEN ms.player_id = GREATEST(m.player_1_id, m.player_2_id) THEN (ms.checkout_completed::FLOAT / NULLIF(ms.checkout_opportunity, 0) * 100) END) AS numeric), 2) AS player_b_co_percent
FROM matches m
JOIN match_stats ms ON m.id = ms.match_id
GROUP BY LEAST(m.player_1_id, m.player_2_id), GREATEST(m.player_1_id, m.player_2_id);

-- =====================================================
-- 11. VIEW: PLAYER CURRENT FORM (Last 5 Matches)
-- =====================================================
CREATE OR REPLACE VIEW player_current_form AS
WITH ranked_matches AS (
    SELECT 
        CASE 
            WHEN m.player_1_id = p.id THEN m.player_1_id
            WHEN m.player_2_id = p.id THEN m.player_2_id
        END AS player_id,
        m.id AS match_id,
        m.match_date,
        m.winner_id,
        CASE WHEN m.winner_id = p.id THEN 'W' ELSE 'L' END AS result,
        ROW_NUMBER() OVER (
            PARTITION BY p.id 
            ORDER BY m.match_date DESC
        ) AS match_rank
    FROM players p
    CROSS JOIN matches m
    WHERE m.player_1_id = p.id OR m.player_2_id = p.id
)
SELECT 
    player_id,
    match_id,
    match_date,
    result,
    match_rank
FROM ranked_matches
WHERE match_rank <= 5;

-- =====================================================
-- 12. VIEW: PLAYER ACHIEVEMENTS
-- =====================================================
CREATE OR REPLACE VIEW player_achievements AS
SELECT 
    e.winner_id AS player_id,
    s.id AS series_id,
    s.series_name,
    e.id AS event_id,
    e.event_number,
    e.event_name,
    e.is_toc,
    e.event_date
FROM events e
JOIN series s ON e.series_id = s.id
WHERE e.winner_id IS NOT NULL
ORDER BY e.event_date DESC;

-- =====================================================
-- 13. FUNCTION: CALCULATE GROUP STANDINGS
-- =====================================================
CREATE OR REPLACE FUNCTION calculate_group_standings(
    p_event_id INTEGER,
    p_group VARCHAR(20)
)
RETURNS TABLE(
    "position" INTEGER,
    player_id INTEGER,
    player_name VARCHAR(100),
    matches_played BIGINT,
    leg_wins BIGINT,
    leg_losses BIGINT,
    leg_difference BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH player_stats AS (
        SELECT 
            p.id,
            p.name,
            COUNT(m.id) AS matches,
            SUM(CASE WHEN m.player_1_id = p.id THEN m.p1_legs ELSE m.p2_legs END) AS wins,
            SUM(CASE WHEN m.player_1_id = p.id THEN m.p2_legs ELSE m.p1_legs END) AS losses
        FROM players p
        JOIN matches m ON (m.player_1_id = p.id OR m.player_2_id = p.id)
        WHERE m.event_id = p_event_id AND m.stage = p_group
        GROUP BY p.id, p.name
    )
    SELECT 
        ROW_NUMBER() OVER (
            ORDER BY wins DESC, (wins - losses) DESC
        )::INTEGER AS position,
        id AS player_id,
        name AS player_name,
        matches AS matches_played,
        wins AS leg_wins,
        losses AS leg_losses,
        (wins - losses) AS leg_difference
    FROM player_stats;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE series ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE match_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE edit_log ENABLE ROW LEVEL SECURITY;

-- Public read access for all tables
CREATE POLICY "Public read access" ON series FOR SELECT USING (true);
CREATE POLICY "Public read access" ON players FOR SELECT USING (true);
CREATE POLICY "Public read access" ON events FOR SELECT USING (true);
CREATE POLICY "Public read access" ON matches FOR SELECT USING (true);
CREATE POLICY "Public read access" ON match_stats FOR SELECT USING (true);
CREATE POLICY "Public read access" ON edit_log FOR SELECT USING (true);

-- Write access requires custom header (x-admin-secret)
-- Note: This will be validated in application code, not at database level
-- For database-level security, use Supabase Auth or custom functions

CREATE POLICY "Admin write access" ON series FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

CREATE POLICY "Admin write access" ON players FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

CREATE POLICY "Admin write access" ON events FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

CREATE POLICY "Admin write access" ON matches FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

CREATE POLICY "Admin write access" ON match_stats FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

CREATE POLICY "Admin write access" ON edit_log FOR ALL 
USING (current_setting('request.headers', true)::json->>'x-admin-secret' = 'YOUR_SECRET_KEY_HERE');

-- =====================================================
-- 15. INITIAL DATA: CREATE SERIES 1
-- =====================================================
INSERT INTO series (series_name, start_year, is_complete)
VALUES ('Series 1', 2025, FALSE);

-- =====================================================
-- SETUP COMPLETE
-- =====================================================
-- Next steps:
-- 1. Create Supabase Storage bucket: player-photos (public)
-- 2. Replace 'YOUR_SECRET_KEY_HERE' with your actual admin secret
-- 3. Enable pg_cron extension in Supabase dashboard
-- 4. Test schema with sample data





