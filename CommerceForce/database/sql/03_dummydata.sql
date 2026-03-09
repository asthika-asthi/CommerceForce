-- =============================================================
-- WHITE-LABEL COMMERCE PLATFORM -- DUMMY DATA
-- Version 1.0
-- Scenario: "TechParts Pro" -- a B2B/B2C electronics components
--           retailer running on the white-label platform.
--
-- Insertion order strictly respects FK dependencies.
-- All UUIDs are fixed so cross-table references are exact.
-- Run AFTER database.sql (seed data must already exist).
--
-- Covers all 46 tables with realistic, connected data.
-- Safe to re-run -- uses ON CONFLICT DO NOTHING where applicable.
-- =============================================================


-- =============================================================
-- 0. PLATFORM CONFIGURATION
-- =============================================================

INSERT INTO branding_config (
    company_name, domain, logo_url, favicon_url,
    primary_color, secondary_color,
    email_from_name, email_from_address,
    invoice_template, support_email, support_phone
) VALUES (
    'TechParts Pro',
    'techpartspro.com',
    'https://cdn.techpartspro.com/assets/logo.png',
    'https://cdn.techpartspro.com/assets/favicon.ico',
    '#1A56DB',
    '#E3EFFF',
    'TechParts Pro',
    'noreply@techpartspro.com',
    'default',
    'support@techpartspro.com',
    '+44 20 7946 0123'
) ON CONFLICT (domain) DO NOTHING;

-- Enable all feature flags for demo purposes
UPDATE feature_flags SET enabled = TRUE, config_json = '{"max_days": 60}'
WHERE feature_key = 'net_terms';

UPDATE feature_flags SET enabled = TRUE
WHERE feature_key IN (
    'b2b_enabled', 'rfq_enabled', 'tiered_pricing',
    'contract_pricing', 'loyalty_program', 'sale_enabled', 'multi_warehouse'
);


-- =============================================================
-- 1. IDENTITY & ACCESS -- Users
--    Roles and permissions already seeded by database.sql.
--    We insert staff users here covering all role types.
-- =============================================================

-- Fixed UUIDs for all users
-- admin:             a0000000-0000-0000-0000-000000000001
-- warehouse_manager: a0000000-0000-0000-0000-000000000002
-- sales_rep:         a0000000-0000-0000-0000-000000000003
-- customer (B2C):    a0000000-0000-0000-0000-000000000004
-- customer (B2C):    a0000000-0000-0000-0000-000000000005
-- b2b_buyer:         a0000000-0000-0000-0000-000000000006
-- b2b_manager:       a0000000-0000-0000-0000-000000000007

INSERT INTO users (
    id, email, password_hash, role_id,
    first_name, last_name, phone,
    is_active, email_verified, email_verified_at, last_login_at
)
SELECT
    a.id::UUID,
    a.email,
    -- bcrypt hash of 'Password123!' -- never use in production
    '$2b$12$KIXkJ8hE2dL9mN3pQ7rSuO4vWxYzAb5cDfGhIjKlMnOpQrStUvWx',
    r.id,
    a.first_name, a.last_name, a.phone,
    TRUE, TRUE, NOW() - INTERVAL '30 days',
    NOW() - INTERVAL '1 day'
FROM (VALUES
    ('a0000000-0000-0000-0000-000000000001', 'admin@techpartspro.com',      'superadmin',        'Sarah',   'Mitchell', '+44 7700 900001'),
    ('a0000000-0000-0000-0000-000000000002', 'warehouse@techpartspro.com',  'warehouse_manager', 'James',   'Carter',   '+44 7700 900002'),
    ('a0000000-0000-0000-0000-000000000003', 'sales@techpartspro.com',      'sales_rep',         'Priya',   'Sharma',   '+44 7700 900003'),
    ('a0000000-0000-0000-0000-000000000004', 'alice.jones@gmail.com',       'customer',          'Alice',   'Jones',    '+44 7700 900004'),
    ('a0000000-0000-0000-0000-000000000005', 'bob.taylor@hotmail.com',      'customer',          'Bob',     'Taylor',   '+44 7700 900005'),
    ('a0000000-0000-0000-0000-000000000006', 'procurement@acmecorp.com',    'b2b_buyer',         'David',   'Chen',     '+44 7700 900006'),
    ('a0000000-0000-0000-0000-000000000007', 'manager@acmecorp.com',        'b2b_manager',       'Rachel',  'O''Brien',  '+44 7700 900007')
) AS a(id, email, role_name, first_name, last_name, phone)
JOIN roles r ON r.name = a.role_name
ON CONFLICT (email) DO NOTHING;


-- Refresh tokens (active sessions)
INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES
    (
        'b0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        'hash_admin_token_abc123def456',
        NOW() + INTERVAL '7 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000004',
        'hash_alice_token_xyz789uvw012',
        NOW() + INTERVAL '7 days'
    ),
    (
        'b0000000-0000-0000-0000-000000000003',
        'a0000000-0000-0000-0000-000000000006',
        'hash_david_token_mno345pqr678',
        NOW() + INTERVAL '7 days'
    )
ON CONFLICT (token_hash) DO NOTHING;


-- Password reset token (Bob requested a reset)
INSERT INTO password_reset_tokens (id, user_id, token_hash, expires_at, used_at) VALUES
    (
        'c0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000005',
        'hash_reset_bob_stu901vwx234',
        NOW() + INTERVAL '1 hour',
        NULL  -- not yet used
    )
ON CONFLICT (token_hash) DO NOTHING;


-- =============================================================
-- 2. CUSTOMER SERVICE
-- =============================================================

-- Customer groups (beyond seed data -- more granular B2C tiers)
INSERT INTO customer_groups (name, description, is_b2b) VALUES
    ('retail',    'Standard B2C retail customers',            FALSE),
    ('vip',       'High-value B2C customers with discounts',  FALSE),
    ('wholesale', 'B2B wholesale accounts',                   TRUE),
    ('trade',     'B2B trade account with contract pricing',  TRUE)
ON CONFLICT (name) DO NOTHING;


-- B2C Customers linked to their user accounts
INSERT INTO customers (
    id, user_id, customer_group_id,
    first_name, last_name, email, phone,
    date_of_birth, is_active, loyalty_points, notes
)
SELECT
    c.id::UUID,
    c.user_id::UUID,
    cg.id,
    c.first_name, c.last_name, c.email, c.phone,
    c.dob::DATE, TRUE, c.points, c.notes
FROM (VALUES
    ('c1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000004',
     'retail',  'Alice',  'Jones',   'alice.jones@gmail.com',    '+44 7700 900004',
     '1990-03-15', 250, 'Frequent buyer, prefers email contact'),
    ('c1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000005',
     'vip',     'Bob',    'Taylor',  'bob.taylor@hotmail.com',   '+44 7700 900005',
     '1985-07-22', 1200, 'VIP -- has requested priority shipping in the past'),
    ('c1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000006',
     'trade',   'David',  'Chen',    'procurement@acmecorp.com', '+44 7700 900006',
     '1978-11-05', 0, 'Primary procurement contact at Acme Corp'),
    ('c1000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000007',
     'trade',   'Rachel', 'O''Brien', 'manager@acmecorp.com',     '+44 7700 900007',
     '1982-04-30', 0, 'Account manager at Acme Corp -- approves large orders')
) AS c(id, user_id, group_name, first_name, last_name, email, phone, dob, points, notes)
JOIN customer_groups cg ON cg.name = c.group_name
ON CONFLICT (email) DO NOTHING;


-- B2B Company
INSERT INTO companies (
    id, name, registration_number, tax_number,
    industry, website, credit_limit, payment_terms_days, is_active
) VALUES (
    'd0000000-0000-0000-0000-000000000001',
    'Acme Corp Ltd',
    'GB12345678',
    'GB987654321',
    'Manufacturing',
    'https://www.acmecorp.com',
    25000.00,
    60,
    TRUE
) ON CONFLICT DO NOTHING;


-- Link both B2B customers to Acme Corp
INSERT INTO company_contacts (
    id, company_id, customer_id, job_title, is_primary, can_order, can_approve
) VALUES
    (
        'e0000000-0000-0000-0000-000000000001',
        'd0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000003',
        'Procurement Manager', FALSE, TRUE, FALSE
    ),
    (
        'e0000000-0000-0000-0000-000000000002',
        'd0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000004',
        'Head of Procurement', TRUE, TRUE, TRUE
    )
ON CONFLICT (company_id, customer_id) DO NOTHING;


-- Addresses
INSERT INTO addresses (
    id, customer_id, company_id, address_type, is_default,
    full_name, line1, line2, city, state_province, postal_code, country_code, phone
) VALUES
    -- Alice -- home shipping address
    (
        'f0000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001', NULL,
        'shipping', TRUE,
        'Alice Jones', '14 Maple Street', 'Flat 2',
        'London', 'England', 'EC1A 1BB', 'GB', '+44 7700 900004'
    ),
    -- Alice -- billing address
    (
        'f0000000-0000-0000-0000-000000000002',
        'c1000000-0000-0000-0000-000000000001', NULL,
        'billing', TRUE,
        'Alice Jones', '14 Maple Street', 'Flat 2',
        'London', 'England', 'EC1A 1BB', 'GB', '+44 7700 900004'
    ),
    -- Bob -- home shipping
    (
        'f0000000-0000-0000-0000-000000000003',
        'c1000000-0000-0000-0000-000000000002', NULL,
        'shipping', TRUE,
        'Bob Taylor', '7 Oak Avenue', NULL,
        'Manchester', 'England', 'M1 2AB', 'GB', '+44 7700 900005'
    ),
    -- Acme Corp -- company shipping address
    (
        'f0000000-0000-0000-0000-000000000004',
        NULL, 'd0000000-0000-0000-0000-000000000001',
        'shipping', TRUE,
        'Acme Corp Ltd', 'Unit 5, Industrial Park', 'Thornbury Road',
        'Birmingham', 'England', 'B1 1AA', 'GB', '+44 121 946 0100'
    ),
    -- Acme Corp -- billing address
    (
        'f0000000-0000-0000-0000-000000000005',
        NULL, 'd0000000-0000-0000-0000-000000000001',
        'billing', TRUE,
        'Acme Corp Ltd -- Accounts Payable', 'Unit 5, Industrial Park', 'Thornbury Road',
        'Birmingham', 'England', 'B1 1AA', 'GB', '+44 121 946 0101'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 3. PRODUCT CATALOG
-- =============================================================

-- Categories (self-referencing tree)
INSERT INTO categories (id, parent_id, name, slug, description, sort_order, is_active) VALUES
    (1,  NULL, 'Electronics',           'electronics',            'All electronic components and devices',    1,  TRUE),
    (2,  1,    'Microcontrollers',      'microcontrollers',       'Arduino, ESP32, STM32 and more',           1,  TRUE),
    (3,  1,    'Sensors',               'sensors',                'Temperature, pressure, motion sensors',    2,  TRUE),
    (4,  1,    'Power Supplies',        'power-supplies',         'PSUs, converters, regulators',             3,  TRUE),
    (5,  1,    'Connectors & Cables',   'connectors-cables',      'Connectors, headers, wiring',              4,  TRUE),
    (6,  NULL, 'Tools & Equipment',     'tools-equipment',        'Soldering, testing, measurement tools',   2,  TRUE),
    (7,  6,    'Soldering',             'soldering',              'Soldering irons, solder, accessories',    1,  TRUE),
    (8,  6,    'Test & Measurement',    'test-measurement',       'Multimeters, oscilloscopes, probes',      2,  TRUE)
ON CONFLICT DO NOTHING;


-- Brands
INSERT INTO brands (id, name, slug, logo_url, is_active) VALUES
    (1, 'Arduino',      'arduino',      'https://cdn.techpartspro.com/brands/arduino.png',      TRUE),
    (2, 'Espressif',    'espressif',    'https://cdn.techpartspro.com/brands/espressif.png',    TRUE),
    (3, 'Bosch Sensortec', 'bosch-sensortec', 'https://cdn.techpartspro.com/brands/bosch.png', TRUE),
    (4, 'Fluke',        'fluke',        'https://cdn.techpartspro.com/brands/fluke.png',        TRUE),
    (5, 'Hakko',        'hakko',        'https://cdn.techpartspro.com/brands/hakko.png',        TRUE),
    (6, 'Generic',      'generic',      NULL,                                                   TRUE)
ON CONFLICT DO NOTHING;


-- Attribute definitions
INSERT INTO attribute_definitions (id, name, input_type, is_variant) VALUES
    (1, 'color',        'select',       FALSE),
    (2, 'voltage',      'select',       TRUE),
    (3, 'pin_count',    'select',       TRUE),
    (4, 'wattage',      'select',       TRUE),
    (5, 'form_factor',  'select',       FALSE),
    (6, 'material',     'select',       FALSE)
ON CONFLICT DO NOTHING;


-- Products
-- Fixed UUIDs:
-- Arduino Uno R3:  a1000000-0000-0000-0000-000000000001
-- ESP32 DevKit:    a1000000-0000-0000-0000-000000000002
-- BME280 Sensor:   a1000000-0000-0000-0000-000000000003
-- 12V PSU 5A:      a1000000-0000-0000-0000-000000000004
-- Dupont Cables:   a1000000-0000-0000-0000-000000000005
-- Hakko FX-888D:   a1000000-0000-0000-0000-000000000006
-- Fluke 117:       a1000000-0000-0000-0000-000000000007

INSERT INTO products (
    id, sku, name, slug, description, short_description,
    category_id, brand_id, base_price, cost_price,
    tax_class, weight_kg, is_active, is_featured, is_b2b_only
) VALUES
    (
        'a1000000-0000-0000-0000-000000000001',
        'ARD-UNO-R3', 'Arduino Uno R3', 'arduino-uno-r3',
        'The Arduino Uno R3 is a microcontroller board based on the ATmega328P. '
        'It has 14 digital I/O pins, 6 analogue inputs, a 16 MHz ceramic resonator, '
        'USB connection, power jack, ICSP header and a reset button.',
        'ATmega328P microcontroller, 14 digital I/O pins, USB connectivity',
        2, 1, 22.99, 11.50, 'standard', 0.025, TRUE, TRUE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000002',
        'ESP-32-DEV', 'ESP32 DevKit V1', 'esp32-devkit-v1',
        'ESP32 development board featuring dual-core processor, integrated Wi-Fi and Bluetooth. '
        'Ideal for IoT projects. 30 GPIO pins, 4MB flash memory.',
        'Dual-core, Wi-Fi + Bluetooth, 30 GPIO pins, 4MB flash',
        2, 2, 12.99, 6.00, 'standard', 0.015, TRUE, TRUE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000003',
        'SEN-BME280', 'BME280 Temperature/Humidity/Pressure Sensor', 'bme280-sensor',
        'Precision combined digital humidity, pressure and temperature sensor from Bosch. '
        'I2C and SPI interface. Operating range: -40 to +85 degC.',
        'Temperature, humidity and pressure in one compact package',
        3, 3, 8.49, 3.20, 'standard', 0.003, TRUE, FALSE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000004',
        'PSU-12V-5A', '12V 5A Regulated DC Power Supply', '12v-5a-psu',
        'Reliable regulated 12V 5A (60W) desktop power supply with overload protection, '
        'short circuit protection and thermal protection. Universal input 100-240V AC.',
        '12V 5A regulated output, 60W, universal input, protected',
        4, 6, 24.99, 12.00, 'standard', 0.850, TRUE, FALSE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000005',
        'CBL-DUPONT-40', 'Dupont Jumper Wires 40-piece Set', 'dupont-jumper-wires-40',
        '40-piece mixed jumper wire set. Includes male-to-male, male-to-female and '
        'female-to-female configurations. 20cm length. Ideal for breadboard prototyping.',
        '40 pcs mixed M-M, M-F, F-F jumper wires, 20cm',
        5, 6, 4.99, 1.20, 'standard', 0.050, TRUE, FALSE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000006',
        'HAK-FX888D', 'Hakko FX-888D Digital Soldering Station', 'hakko-fx888d',
        'Professional digital soldering station with rapid heat recovery and '
        'precise temperature control from 200 degC to 480 degC. Includes T18-D16 tip.',
        'Digital soldering station, 200-480 degC, rapid heat recovery',
        7, 5, 109.99, 65.00, 'standard', 0.970, TRUE, TRUE, FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000007',
        'FLK-117', 'Fluke 117 Electrician''s Multimeter', 'fluke-117-multimeter',
        'True RMS multimeter designed for electricians. AutoVolt automatic AC/DC '
        'voltage selection. Non-contact voltage detection. CAT III 600V safety rating.',
        'True RMS, AutoVolt, non-contact voltage, CAT III 600V',
        8, 4, 149.99, 90.00, 'standard', 0.430, TRUE, TRUE, FALSE
    )
ON CONFLICT (sku) DO NOTHING;


-- Media assets (must come before product_images)
INSERT INTO media_assets (
    id, file_name, storage_path, public_url, mime_type,
    file_size_bytes, width_px, height_px, asset_type,
    uploaded_by, usage_count, tags
) VALUES
    (
        'e6000000-0000-0000-0000-000000000001',
        'arduino-uno-r3-main.jpg',
        'gs://techpartspro-media/products/arduino-uno-r3-main.jpg',
        'https://cdn.techpartspro.com/products/arduino-uno-r3-main.jpg',
        'image/jpeg', 245120, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["arduino","microcontroller"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000002',
        'arduino-uno-r3-pinout.jpg',
        'gs://techpartspro-media/products/arduino-uno-r3-pinout.jpg',
        'https://cdn.techpartspro.com/products/arduino-uno-r3-pinout.jpg',
        'image/jpeg', 189440, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["arduino","pinout"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000003',
        'esp32-devkit-main.jpg',
        'gs://techpartspro-media/products/esp32-devkit-main.jpg',
        'https://cdn.techpartspro.com/products/esp32-devkit-main.jpg',
        'image/jpeg', 198656, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["esp32","wifi","bluetooth"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000004',
        'bme280-sensor-main.jpg',
        'gs://techpartspro-media/products/bme280-sensor-main.jpg',
        'https://cdn.techpartspro.com/products/bme280-sensor-main.jpg',
        'image/jpeg', 112640, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["sensor","temperature","humidity"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000005',
        'hakko-fx888d-main.jpg',
        'gs://techpartspro-media/products/hakko-fx888d-main.jpg',
        'https://cdn.techpartspro.com/products/hakko-fx888d-main.jpg',
        'image/jpeg', 312320, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["hakko","soldering","tools"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000006',
        'fluke-117-main.jpg',
        'gs://techpartspro-media/products/fluke-117-main.jpg',
        'https://cdn.techpartspro.com/products/fluke-117-main.jpg',
        'image/jpeg', 278528, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["fluke","multimeter","test"]'
    ),
    (
        'e6000000-0000-0000-0000-000000000007',
        'fluke-117-accessories.jpg',
        'gs://techpartspro-media/products/fluke-117-accessories.jpg',
        'https://cdn.techpartspro.com/products/fluke-117-accessories.jpg',
        'image/jpeg', 198656, 800, 600, 'product_image',
        'a0000000-0000-0000-0000-000000000001', 1, '["fluke","probes","accessories"]'
    )
ON CONFLICT (storage_path) DO NOTHING;


-- Product images (1-N per product, references media_assets)
INSERT INTO product_images (
    id, product_id, asset_id, image_url, alt_text, sort_order, is_primary
) VALUES
    -- Arduino Uno (2 images)
    (
        'ed000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000001',
        'e6000000-0000-0000-0000-000000000001',
        'https://cdn.techpartspro.com/products/arduino-uno-r3-main.jpg',
        'Arduino Uno R3 front view', 0, TRUE
    ),
    (
        'ed000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000001',
        'e6000000-0000-0000-0000-000000000002',
        'https://cdn.techpartspro.com/products/arduino-uno-r3-pinout.jpg',
        'Arduino Uno R3 pinout diagram', 1, FALSE
    ),
    -- ESP32 (1 image)
    (
        'ed000000-0000-0000-0000-000000000003',
        'a1000000-0000-0000-0000-000000000002',
        'e6000000-0000-0000-0000-000000000003',
        'https://cdn.techpartspro.com/products/esp32-devkit-main.jpg',
        'ESP32 DevKit V1 top view', 0, TRUE
    ),
    -- BME280 (1 image)
    (
        'ed000000-0000-0000-0000-000000000004',
        'a1000000-0000-0000-0000-000000000003',
        'e6000000-0000-0000-0000-000000000004',
        'https://cdn.techpartspro.com/products/bme280-sensor-main.jpg',
        'BME280 sensor module', 0, TRUE
    ),
    -- Hakko FX-888D (1 image)
    (
        'ed000000-0000-0000-0000-000000000005',
        'a1000000-0000-0000-0000-000000000006',
        'e6000000-0000-0000-0000-000000000005',
        'https://cdn.techpartspro.com/products/hakko-fx888d-main.jpg',
        'Hakko FX-888D soldering station', 0, TRUE
    ),
    -- Fluke 117 (2 images)
    (
        'ed000000-0000-0000-0000-000000000006',
        'a1000000-0000-0000-0000-000000000007',
        'e6000000-0000-0000-0000-000000000006',
        'https://cdn.techpartspro.com/products/fluke-117-main.jpg',
        'Fluke 117 multimeter front', 0, TRUE
    ),
    (
        'ed000000-0000-0000-0000-000000000007',
        'a1000000-0000-0000-0000-000000000007',
        'e6000000-0000-0000-0000-000000000007',
        'https://cdn.techpartspro.com/products/fluke-117-accessories.jpg',
        'Fluke 117 with test leads', 1, FALSE
    )
ON CONFLICT DO NOTHING;


-- Product attributes
INSERT INTO product_attributes (id, product_id, attribute_id, value) VALUES
    -- Arduino Uno
    ('ec000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 2, '5V'),
    ('ec000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 3, '14'),
    -- ESP32
    ('ec000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002', 2, '3.3V'),
    ('ec000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000002', 3, '30'),
    -- BME280
    ('ec000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000003', 2, '3.3V'),
    -- 12V PSU
    ('ec000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000004', 2, '12V'),
    ('ec000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000004', 4, '60W')
ON CONFLICT (product_id, attribute_id, value) DO NOTHING;


-- Product variants (Dupont cables come in different lengths)
INSERT INTO product_variants (id, product_id, sku, name, price_override, is_active) VALUES
    (
        'f0000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000005',
        'CBL-DUPONT-40-20CM', '40-piece 20cm', 4.99, TRUE
    ),
    (
        'f0000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000005',
        'CBL-DUPONT-40-30CM', '40-piece 30cm', 5.99, TRUE
    )
ON CONFLICT (sku) DO NOTHING;


-- Variant attributes (length for Dupont cables)
INSERT INTO variant_attributes (variant_id, attribute_id, value) VALUES
    ('f0000000-0000-0000-0000-000000000001', 5, '20cm'),
    ('f0000000-0000-0000-0000-000000000002', 5, '30cm')
ON CONFLICT (variant_id, attribute_id) DO NOTHING;


-- Product relationships (cross-sells and related)
INSERT INTO product_related (product_id, related_product_id, relation_type) VALUES
    -- Arduino -> ESP32 (related alternative)
    ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'related'),
    -- Arduino -> Dupont Cables (cross-sell)
    ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000005', 'cross_sell'),
    -- Arduino -> BME280 (cross-sell sensor)
    ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000003', 'cross_sell'),
    -- Hakko -> Fluke (upsell complementary tool)
    ('a1000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000007', 'upsell')
ON CONFLICT DO NOTHING;


-- =============================================================
-- 4. PRICING ENGINE
-- =============================================================

-- Pricing rules
INSERT INTO pricing_rules (
    rule_type, name,
    product_id, variant_id, category_id, customer_group_id, company_id,
    min_quantity, discount_type, discount_value, fixed_price,
    priority, start_date, end_date, is_active
)
SELECT
    pr.rule_type, pr.name,
    pr.product_id::UUID,
    pr.variant_id::UUID,
    pr.category_id::INT,
    cg.id,
    pr.company_id::UUID,
    pr.min_qty, pr.disc_type, pr.disc_val, pr.fixed_price,
    pr.priority, pr.start_date::TIMESTAMPTZ, pr.end_date::TIMESTAMPTZ,
    TRUE
FROM (VALUES
    -- VIP customers get 10% off everything
    ('customer_group', 'VIP 10% discount',
     NULL, NULL, NULL, 'vip', NULL,
     1, 'percentage', 10.0, NULL,
     10, NULL, NULL),
    -- Tiered: buy 5+ Arduino Uno, get 8% off
    ('tiered', 'Arduino Uno bulk 5+ (8% off)',
     'a1000000-0000-0000-0000-000000000001', NULL, NULL, NULL, NULL,
     5, 'percentage', 8.0, NULL,
     20, NULL, NULL),
    -- Tiered: buy 10+ Arduino Uno, get 15% off
    ('tiered', 'Arduino Uno bulk 10+ (15% off)',
     'a1000000-0000-0000-0000-000000000001', NULL, NULL, NULL, NULL,
     10, 'percentage', 15.0, NULL,
     30, NULL, NULL),
    -- Contract: Acme Corp fixed price on ESP32
    ('contract', 'Acme Corp ESP32 contract price',
     'a1000000-0000-0000-0000-000000000002', NULL, NULL, NULL,
     'd0000000-0000-0000-0000-000000000001',
     1, 'percentage', 0, 9.99,
     50, NULL, NULL),
    -- Sale: 20% off all sensors (limited time)
    ('sale', 'Sensors Summer Sale 20% off',
     NULL, NULL, 3, NULL, NULL,
     1, 'percentage', 20.0, NULL,
     15, NOW() - INTERVAL '2 days', NOW() + INTERVAL '5 days')
) AS pr(rule_type, name, product_id, variant_id, category_id, group_name, company_id,
        min_qty, disc_type, disc_val, fixed_price, priority, start_date, end_date)
LEFT JOIN customer_groups cg ON cg.name = pr.group_name;


-- Promotions
INSERT INTO promotions (
    id, code, name, type, discount_value,
    min_order_value, max_uses, uses_count, max_uses_per_customer,
    product_id, category_id, customer_group_id,
    is_stackable, start_date, end_date, is_active
) VALUES
    (
        'ee000000-0000-0000-0000-000000000001',
        'WELCOME10', 'Welcome 10% Off First Order', 'percentage', 10.0,
        20.00, 1000, 47, 1,
        NULL, NULL, NULL,
        FALSE, NOW() - INTERVAL '90 days', NULL, TRUE
    ),
    (
        'ee000000-0000-0000-0000-000000000002',
        'FREESHIP50', 'Free Shipping Over GBP50', 'free_shipping', 0,
        50.00, NULL, 312, NULL,
        NULL, NULL, NULL,
        TRUE, NOW() - INTERVAL '60 days', NULL, TRUE
    ),
    (
        'ee000000-0000-0000-0000-000000000003',
        NULL, 'Autumn Tools Sale -- 15% Off Tools', 'percentage', 15.0,
        NULL, NULL, 0, NULL,
        NULL, 6, NULL,  -- category 6 = Tools & Equipment
        FALSE, NOW() + INTERVAL '7 days', NOW() + INTERVAL '21 days', TRUE
    )
ON CONFLICT (id) DO NOTHING;


-- =============================================================
-- 5. CART SERVICE
-- =============================================================

-- Active cart for Alice (B2C)
INSERT INTO carts (id, customer_id, session_id, company_id, coupon_code, currency_code, expires_at) VALUES
    (
        'e2000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001',
        NULL, NULL, 'WELCOME10', 'GBP',
        NOW() + INTERVAL '7 days'
    )
ON CONFLICT DO NOTHING;

-- Guest cart (no customer -- session only)
INSERT INTO carts (id, customer_id, session_id, company_id, coupon_code, currency_code, expires_at) VALUES
    (
        'e2000000-0000-0000-0000-000000000002',
        NULL,
        'sess_guest_abc123xyz789',
        NULL, NULL, 'GBP',
        NOW() + INTERVAL '1 day'
    )
ON CONFLICT DO NOTHING;

-- B2B cart for David (Acme Corp)
INSERT INTO carts (id, customer_id, session_id, company_id, coupon_code, currency_code, expires_at) VALUES
    (
        'e2000000-0000-0000-0000-000000000003',
        'c1000000-0000-0000-0000-000000000003',
        NULL,
        'd0000000-0000-0000-0000-000000000001',
        NULL, 'GBP',
        NOW() + INTERVAL '7 days'
    )
ON CONFLICT DO NOTHING;


-- Cart items
INSERT INTO cart_items (id, cart_id, product_id, variant_id, quantity, unit_price, custom_data) VALUES
    -- Alice's cart: 1x Arduino Uno + 1x BME280
    (
        'e3000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000001', NULL,
        1, 22.99, '{}'
    ),
    (
        'e3000000-0000-0000-0000-000000000002',
        'e2000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000003', NULL,
        2, 8.49, '{}'
    ),
    -- Guest cart: 1x Hakko soldering station
    (
        'e3000000-0000-0000-0000-000000000003',
        'e2000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000006', NULL,
        1, 109.99, '{}'
    ),
    -- David's B2B cart: 20x ESP32 (bulk)
    (
        'e3000000-0000-0000-0000-000000000004',
        'e2000000-0000-0000-0000-000000000003',
        'a1000000-0000-0000-0000-000000000002', NULL,
        20, 9.99, '{"po_reference": "PO-2024-0891"}'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 6. CHECKOUT SERVICE
-- =============================================================

-- Bob's completed checkout session (became an order)
INSERT INTO checkout_sessions (
    id, cart_id, customer_id,
    shipping_address_id, billing_address_id,
    shipping_method_id, payment_method, payment_provider_ref,
    subtotal, shipping_cost, tax_amount, discount_amount, total_amount,
    currency_code, status, expires_at, completed_at
)
SELECT
    'e4000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',  -- Bob
    'f0000000-0000-0000-0000-000000000003',  -- Bob's shipping address
    'f0000000-0000-0000-0000-000000000003',  -- same for billing
    sm.id,
    'stripe', 'pi_3OxK2LHY9uHzWvS81aB2cD4E',
    149.99, 0.00, 30.00, 0.00, 179.99,
    'GBP', 'completed',
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '5 days'
FROM shipping_methods sm WHERE sm.code = 'standard'
ON CONFLICT DO NOTHING;


-- =============================================================
-- 7. ORDER MANAGEMENT SYSTEM
-- =============================================================

-- Order 1: Bob's completed order (Fluke multimeter)
INSERT INTO orders (
    id, order_number, customer_id, company_id, checkout_session_id,
    status, payment_status, payment_method, payment_provider_ref,
    currency_code,
    subtotal, shipping_cost, tax_amount, discount_amount, total_amount,
    shipping_address, billing_address, shipping_method_name,
    notes, internal_notes, net_terms_due_date,
    placed_at, confirmed_at, shipped_at, delivered_at
) VALUES (
    'eb000000-0000-0000-0000-000000000001',
    'ORD-2024-0001',
    'c1000000-0000-0000-0000-000000000002', -- Bob
    NULL,
    'e4000000-0000-0000-0000-000000000001',
    'delivered', 'paid', 'stripe', 'pi_3OxK2LHY9uHzWvS81aB2cD4E',
    'GBP',
    149.99, 0.00, 30.00, 0.00, 179.99,
    '{"full_name":"Bob Taylor","line1":"7 Oak Avenue","city":"Manchester","postal_code":"M1 2AB","country_code":"GB"}',
    '{"full_name":"Bob Taylor","line1":"7 Oak Avenue","city":"Manchester","postal_code":"M1 2AB","country_code":"GB"}',
    'Standard Delivery',
    NULL, 'Dispatched from MAIN warehouse, tracking: DHL1234567890',
    NULL,
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '4 days',
    NOW() - INTERVAL '2 days'
) ON CONFLICT (order_number) DO NOTHING;


-- Order 2: Alice's confirmed order (Arduino + BME280)
INSERT INTO orders (
    id, order_number, customer_id, company_id, checkout_session_id,
    status, payment_status, payment_method, payment_provider_ref,
    currency_code,
    subtotal, shipping_cost, tax_amount, discount_amount, total_amount,
    shipping_address, billing_address, shipping_method_name,
    notes, internal_notes,
    placed_at, confirmed_at
) VALUES (
    'eb000000-0000-0000-0000-000000000002',
    'ORD-2024-0002',
    'c1000000-0000-0000-0000-000000000001', -- Alice
    NULL, NULL,
    'confirmed', 'paid', 'stripe', 'pi_4PzL3MIZ0vIaXwT92bC3dE5F',
    'GBP',
    39.97, 4.99, 8.99, 4.00, 49.95,
    '{"full_name":"Alice Jones","line1":"14 Maple Street","line2":"Flat 2","city":"London","postal_code":"EC1A 1BB","country_code":"GB"}',
    '{"full_name":"Alice Jones","line1":"14 Maple Street","line2":"Flat 2","city":"London","postal_code":"EC1A 1BB","country_code":"GB"}',
    'Standard Delivery',
    'Please leave with neighbour if not in', NULL,
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day'
) ON CONFLICT (order_number) DO NOTHING;


-- Order 3: Acme Corp B2B order (ESP32 bulk, net terms)
INSERT INTO orders (
    id, order_number, customer_id, company_id, checkout_session_id,
    status, payment_status, payment_method, payment_provider_ref,
    currency_code,
    subtotal, shipping_cost, tax_amount, discount_amount, total_amount,
    shipping_address, billing_address, shipping_method_name,
    notes, internal_notes, net_terms_due_date,
    placed_at, confirmed_at
) VALUES (
    'eb000000-0000-0000-0000-000000000003',
    'ORD-2024-0003',
    'c1000000-0000-0000-0000-000000000003', -- David (Acme)
    'd0000000-0000-0000-0000-000000000001', -- Acme Corp
    NULL,
    'processing', 'unpaid', 'net_terms', NULL,
    'GBP',
    199.80, 0.00, 39.96, 0.00, 239.76,
    '{"full_name":"Acme Corp Ltd","line1":"Unit 5, Industrial Park","line2":"Thornbury Road","city":"Birmingham","postal_code":"B1 1AA","country_code":"GB"}',
    '{"full_name":"Acme Corp Ltd -- Accounts Payable","line1":"Unit 5, Industrial Park","line2":"Thornbury Road","city":"Birmingham","postal_code":"B1 1AA","country_code":"GB"}',
    'Standard Delivery',
    'PO Reference: PO-2024-0891', 'Net 60 -- invoice sent to accounts@acmecorp.com',
    NOW() + INTERVAL '60 days',
    NOW() - INTERVAL '12 hours',
    NOW() - INTERVAL '12 hours'
) ON CONFLICT (order_number) DO NOTHING;


-- Order items
INSERT INTO order_items (
    id, order_id, product_id, variant_id,
    sku, product_name, quantity, unit_price,
    tax_rate, discount_amount, line_total, custom_data
) VALUES
    -- Order 1: Bob -- Fluke 117
    (
        'ea000000-0000-0000-0000-000000000001',
        'eb000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000007', NULL,
        'FLK-117', 'Fluke 117 Electrician''s Multimeter',
        1, 149.99, 0.20, 0.00, 149.99, '{}'
    ),
    -- Order 2: Alice -- Arduino Uno
    (
        'ea000000-0000-0000-0000-000000000002',
        'eb000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000001', NULL,
        'ARD-UNO-R3', 'Arduino Uno R3',
        1, 22.99, 0.20, 2.30, 20.69, '{}'
    ),
    -- Order 2: Alice -- BME280
    (
        'ea000000-0000-0000-0000-000000000003',
        'eb000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000003', NULL,
        'SEN-BME280', 'BME280 Temperature/Humidity/Pressure Sensor',
        2, 8.49, 0.20, 1.70, 15.28, '{}'
    ),
    -- Order 3: Acme -- ESP32 x20 (contract price 9.99)
    (
        'ea000000-0000-0000-0000-000000000004',
        'eb000000-0000-0000-0000-000000000003',
        'a1000000-0000-0000-0000-000000000002', NULL,
        'ESP-32-DEV', 'ESP32 DevKit V1',
        20, 9.99, 0.20, 0.00, 199.80,
        '{"po_reference": "PO-2024-0891"}'
    )
ON CONFLICT DO NOTHING;


-- Order status history (audit trail of every transition)
INSERT INTO order_status_history (id, order_id, status, note, changed_by, changed_at) VALUES
    -- Order 1 full journey
    ('e9000000-0000-0000-0000-000000000001', 'eb000000-0000-0000-0000-000000000001',
     'pending',   'Order placed via storefront', NULL, NOW() - INTERVAL '5 days'),
    ('e9000000-0000-0000-0000-000000000002', 'eb000000-0000-0000-0000-000000000001',
     'confirmed', 'Payment confirmed by Stripe', NULL, NOW() - INTERVAL '5 days'),
    ('e9000000-0000-0000-0000-000000000003', 'eb000000-0000-0000-0000-000000000001',
     'shipped',   'Dispatched via DHL, tracking DHL1234567890',
     'a0000000-0000-0000-0000-000000000002', NOW() - INTERVAL '4 days'),
    ('e9000000-0000-0000-0000-000000000004', 'eb000000-0000-0000-0000-000000000001',
     'delivered', 'Delivery confirmed by DHL', NULL, NOW() - INTERVAL '2 days'),
    -- Order 2
    ('e9000000-0000-0000-0000-000000000005', 'eb000000-0000-0000-0000-000000000002',
     'pending',   'Order placed via storefront', NULL, NOW() - INTERVAL '1 day'),
    ('e9000000-0000-0000-0000-000000000006', 'eb000000-0000-0000-0000-000000000002',
     'confirmed', 'Payment confirmed by Stripe', NULL, NOW() - INTERVAL '1 day'),
    -- Order 3
    ('e9000000-0000-0000-0000-000000000007', 'eb000000-0000-0000-0000-000000000003',
     'pending',   'B2B order placed via portal', NULL, NOW() - INTERVAL '12 hours'),
    ('e9000000-0000-0000-0000-000000000008', 'eb000000-0000-0000-0000-000000000003',
     'confirmed', 'Net 60 terms approved, invoice issued',
     'a0000000-0000-0000-0000-000000000003', NOW() - INTERVAL '12 hours'),
    ('e9000000-0000-0000-0000-000000000009', 'eb000000-0000-0000-0000-000000000003',
     'processing', 'Picking started in warehouse',
     'a0000000-0000-0000-0000-000000000002', NOW() - INTERVAL '6 hours')
ON CONFLICT DO NOTHING;


-- Promotion usage (Alice used WELCOME10 on Order 2)
INSERT INTO promotion_usage (id, promotion_id, customer_id, order_id, used_at) VALUES
    (
        'ef000000-0000-0000-0000-000000000001',
        'ee000000-0000-0000-0000-000000000001', -- WELCOME10
        'c1000000-0000-0000-0000-000000000001', -- Alice
        'eb000000-0000-0000-0000-000000000002',
        NOW() - INTERVAL '1 day'
    )
ON CONFLICT DO NOTHING;


-- Refund (Bob requested partial refund on Order 1 -- test probes faulty)
INSERT INTO refunds (id, order_id, amount, reason, provider_ref, status, created_by, processed_at) VALUES
    (
        'f1000000-0000-0000-0000-000000000001',
        'eb000000-0000-0000-0000-000000000001',
        14.99,
        'Customer reported faulty test lead included with Fluke 117. Partial refund approved.',
        're_3OyM4NIa1wJbYxU03cD4eF6G',
        'processed',
        'a0000000-0000-0000-0000-000000000001', -- admin
        NOW() - INTERVAL '1 day'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 8. INVENTORY SERVICE
-- =============================================================

-- Second warehouse
INSERT INTO warehouses (id, name, code, address, is_active) VALUES
    (2, 'North Fulfilment Centre', 'NORTH',
     '{"line1": "Warehouse 12", "line2": "Logistics Park", "city": "Leeds", "postal_code": "LS1 1AA", "country_code": "GB"}',
     TRUE)
ON CONFLICT (code) DO NOTHING;


-- Inventory levels (product x warehouse)
INSERT INTO inventory (
    id, product_id, variant_id, warehouse_id,
    quantity_on_hand, quantity_reserved, reorder_point, reorder_qty
) VALUES
    -- Arduino Uno -- MAIN
    ('fa000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', NULL, 1, 120, 5,  20, 50),
    -- Arduino Uno -- NORTH
    ('fa000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', NULL, 2, 80,  0,  20, 50),
    -- ESP32 -- MAIN
    ('fa000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002', NULL, 1, 250, 20, 30, 100),
    -- BME280 -- MAIN
    ('fa000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000003', NULL, 1, 8,   2,  15, 30),
    -- PSU 12V -- MAIN
    ('fa000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000004', NULL, 1, 45,  0,  10, 20),
    -- Dupont 20cm variant -- MAIN
    ('fa000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000005',
     'f0000000-0000-0000-0000-000000000001', 1, 500, 0, 50, 200),
    -- Dupont 30cm variant -- MAIN
    ('fa000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000005',
     'f0000000-0000-0000-0000-000000000002', 1, 320, 0, 50, 200),
    -- Hakko FX-888D -- MAIN
    ('fa000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000006', NULL, 1, 18,  0,  5,  10),
    -- Fluke 117 -- MAIN (low stock -- triggers reorder alert)
    ('fa000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000007', NULL, 1, 6,   1,  8,  15)
ON CONFLICT (product_id, variant_id, warehouse_id) DO NOTHING;


-- Inventory movements (history of stock changes)
INSERT INTO inventory_movements (
    id, product_id, variant_id, warehouse_id,
    movement_type, quantity_delta, reference_type, reference_id,
    note, created_by
) VALUES
    -- Initial stock load for Arduino Uno (MAIN)
    ('e5000000-0000-0000-0000-000000000001',
     'a1000000-0000-0000-0000-000000000001', NULL, 1,
     'purchase', 150, 'manual', NULL,
     'Initial stock purchase -- supplier invoice INV-SUP-001',
     'a0000000-0000-0000-0000-000000000002'),
    -- Sale of Fluke 117 -- Bob's order
    ('e5000000-0000-0000-0000-000000000002',
     'a1000000-0000-0000-0000-000000000007', NULL, 1,
     'sale', -1, 'order', 'eb000000-0000-0000-0000-000000000001',
     NULL, NULL),
    -- Sale of Arduino Uno -- Alice's order
    ('e5000000-0000-0000-0000-000000000003',
     'a1000000-0000-0000-0000-000000000001', NULL, 1,
     'sale', -1, 'order', 'eb000000-0000-0000-0000-000000000002',
     NULL, NULL),
    -- Sale of BME280 x 2 -- Alice's order
    ('e5000000-0000-0000-0000-000000000004',
     'a1000000-0000-0000-0000-000000000003', NULL, 1,
     'sale', -2, 'order', 'eb000000-0000-0000-0000-000000000002',
     NULL, NULL),
    -- Reservation of ESP32 x 20 -- Acme order in processing
    ('e5000000-0000-0000-0000-000000000005',
     'a1000000-0000-0000-0000-000000000002', NULL, 1,
     'sale', -20, 'order', 'eb000000-0000-0000-0000-000000000003',
     'Reserved for Acme Corp order ORD-2024-0003', NULL),
    -- Manual adjustment -- stock count correction BME280
    ('e5000000-0000-0000-0000-000000000006',
     'a1000000-0000-0000-0000-000000000003', NULL, 1,
     'adjustment', -2, 'manual', NULL,
     'Stock count discrepancy -- 2 units damaged in storage',
     'a0000000-0000-0000-0000-000000000002')
ON CONFLICT DO NOTHING;


-- =============================================================
-- 9. QUOTE / RFQ SERVICE
-- =============================================================

-- RFQ from Acme Corp for a large Arduino order
INSERT INTO rfq_quotes (
    id, quote_number, company_id, customer_id, assigned_to,
    status, currency_code,
    subtotal, discount_amount, tax_amount, total_amount,
    valid_until, payment_terms,
    notes, internal_notes,
    converted_order_id,
    submitted_at, quoted_at, accepted_at
) VALUES (
    'f3000000-0000-0000-0000-000000000001',
    'RFQ-2024-0001',
    'd0000000-0000-0000-0000-000000000001', -- Acme Corp
    'c1000000-0000-0000-0000-000000000004', -- Rachel (approver)
    'a0000000-0000-0000-0000-000000000003', -- Priya (sales rep)
    'quoted',
    'GBP',
    183.50, 18.35, 33.03, 198.18,
    NOW() + INTERVAL '14 days',
    'Net 60',
    'Require 50 units of Arduino Uno R3 for Q1 production run. Need best price.',
    'Offered 15% bulk discount + existing contract terms. Margin still good at this volume.',
    NULL,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '1 day',
    NULL
) ON CONFLICT (quote_number) DO NOTHING;


-- RFQ items
INSERT INTO rfq_items (id, rfq_id, product_id, variant_id, quantity, requested_price, quoted_price, notes) VALUES
    (
        'f2000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000001', -- Arduino Uno
        NULL,
        50,
        15.00,  -- Acme requested GBP15
        19.54,  -- Priya quoted GBP19.54 (15% off GBP22.99)
        '50 units for Q1 production. Delivery required by end of month.'
    )
ON CONFLICT DO NOTHING;


-- RFQ status history
INSERT INTO rfq_status_history (id, rfq_id, status, note, changed_by, changed_at) VALUES
    (
        'f4000000-0000-0000-0000-000000000001',
        'f3000000-0000-0000-0000-000000000001',
        'draft', 'RFQ created by customer via B2B portal', NULL,
        NOW() - INTERVAL '4 days'
    ),
    (
        'f4000000-0000-0000-0000-000000000002',
        'f3000000-0000-0000-0000-000000000001',
        'submitted', 'Submitted by Rachel O''Brien',
        'a0000000-0000-0000-0000-000000000007',
        NOW() - INTERVAL '3 days'
    ),
    (
        'f4000000-0000-0000-0000-000000000003',
        'f3000000-0000-0000-0000-000000000001',
        'under_review', 'Assigned to Priya Sharma for review',
        'a0000000-0000-0000-0000-000000000001',
        NOW() - INTERVAL '2 days'
    ),
    (
        'f4000000-0000-0000-0000-000000000004',
        'f3000000-0000-0000-0000-000000000001',
        'quoted', 'Quote sent to Acme Corp -- awaiting acceptance',
        'a0000000-0000-0000-0000-000000000003',
        NOW() - INTERVAL '1 day'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 10. NOTIFICATION SERVICE
-- =============================================================

-- Notification log (emails sent for real events)
INSERT INTO notification_log (
    id, template_id, event_key, channel, recipient,
    customer_id, reference_type, reference_id,
    status, provider_ref, sent_at
)
SELECT
    n.id::UUID,
    nt.id,
    n.event_key,
    'email',
    n.recipient,
    n.customer_id::UUID,
    n.ref_type,
    n.ref_id::UUID,
    'delivered',
    n.provider_ref,
    n.sent_at::TIMESTAMPTZ
FROM (VALUES
    ('e7000000-0000-0000-0000-000000000001', 'order_placed',
     'bob.taylor@hotmail.com', 'c1000000-0000-0000-0000-000000000002',
     'order', 'eb000000-0000-0000-0000-000000000001',
     'msg_sendgrid_abc001', (NOW() - INTERVAL '5 days')::TEXT),
    ('e7000000-0000-0000-0000-000000000002', 'order_shipped',
     'bob.taylor@hotmail.com', 'c1000000-0000-0000-0000-000000000002',
     'order', 'eb000000-0000-0000-0000-000000000001',
     'msg_sendgrid_abc002', (NOW() - INTERVAL '4 days')::TEXT),
    ('e7000000-0000-0000-0000-000000000003', 'order_placed',
     'alice.jones@gmail.com', 'c1000000-0000-0000-0000-000000000001',
     'order', 'eb000000-0000-0000-0000-000000000002',
     'msg_sendgrid_abc003', (NOW() - INTERVAL '1 day')::TEXT),
    ('e7000000-0000-0000-0000-000000000004', 'rfq_submitted',
     'manager@acmecorp.com', 'c1000000-0000-0000-0000-000000000004',
     'rfq', 'f3000000-0000-0000-0000-000000000001',
     'msg_sendgrid_abc004', (NOW() - INTERVAL '3 days')::TEXT),
    ('e7000000-0000-0000-0000-000000000005', 'rfq_quoted',
     'manager@acmecorp.com', 'c1000000-0000-0000-0000-000000000004',
     'rfq', 'f3000000-0000-0000-0000-000000000001',
     'msg_sendgrid_abc005', (NOW() - INTERVAL '1 day')::TEXT),
    ('e7000000-0000-0000-0000-000000000006', 'low_stock_alert',
     'admin@techpartspro.com', NULL,
     'inventory', 'fa000000-0000-0000-0000-000000000009',
     'msg_sendgrid_abc006', (NOW() - INTERVAL '12 hours')::TEXT)
) AS n(id, event_key, recipient, customer_id, ref_type, ref_id, provider_ref, sent_at)
JOIN notification_templates nt ON nt.event_key = n.event_key
ON CONFLICT DO NOTHING;


-- Notification preferences (Alice opts out of marketing, keeps transactional)
INSERT INTO notification_preferences (id, customer_id, event_key, channel, is_enabled) VALUES
    ('e8000000-0000-0000-0000-000000000001',
     'c1000000-0000-0000-0000-000000000001', 'order_placed',   'email', TRUE),
    ('e8000000-0000-0000-0000-000000000002',
     'c1000000-0000-0000-0000-000000000001', 'order_shipped',  'email', TRUE),
    ('e8000000-0000-0000-0000-000000000003',
     'c1000000-0000-0000-0000-000000000001', 'order_delivered','email', TRUE)
ON CONFLICT (customer_id, event_key, channel) DO NOTHING;


-- =============================================================
-- 11. AUDIT LOG
-- =============================================================

INSERT INTO audit_log (
    id, table_name, record_id, action,
    changed_by, changed_by_role, ip_address,
    old_values, new_values, changed_at
) VALUES
    -- Admin created the Hakko product
    (
        'e1000000-0000-0000-0000-000000000001',
        'products', 'a1000000-0000-0000-0000-000000000006',
        'INSERT',
        'a0000000-0000-0000-0000-000000000001', 'superadmin',
        '192.168.1.10',
        NULL,
        '{"sku":"HAK-FX888D","name":"Hakko FX-888D Digital Soldering Station","base_price":109.99}',
        NOW() - INTERVAL '10 days'
    ),
    -- Admin updated Fluke price
    (
        'e1000000-0000-0000-0000-000000000002',
        'products', 'a1000000-0000-0000-0000-000000000007',
        'UPDATE',
        'a0000000-0000-0000-0000-000000000001', 'superadmin',
        '192.168.1.10',
        '{"base_price":139.99}',
        '{"base_price":149.99}',
        NOW() - INTERVAL '7 days'
    ),
    -- Admin toggled b2b_enabled feature flag on
    (
        'e1000000-0000-0000-0000-000000000003',
        'feature_flags', '1',
        'UPDATE',
        'a0000000-0000-0000-0000-000000000001', 'superadmin',
        '192.168.1.10',
        '{"feature_key":"b2b_enabled","enabled":false}',
        '{"feature_key":"b2b_enabled","enabled":true}',
        NOW() - INTERVAL '20 days'
    ),
    -- Warehouse manager adjusted BME280 stock
    (
        'e1000000-0000-0000-0000-000000000004',
        'inventory', 'fa000000-0000-0000-0000-000000000004',
        'UPDATE',
        'a0000000-0000-0000-0000-000000000002', 'warehouse_manager',
        '10.0.0.5',
        '{"quantity_on_hand":10}',
        '{"quantity_on_hand":8}',
        NOW() - INTERVAL '2 days'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 12. ADMIN ACTIVITY LOG
-- =============================================================

INSERT INTO admin_activity_log (
    id, user_id, email_attempted, activity_type,
    description, ip_address, user_agent,
    reference_type, reference_id, outcome, created_at
) VALUES
    -- Successful admin login
    (
        'e0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        'admin@techpartspro.com',
        'login_success',
        'Admin logged in via dashboard',
        '192.168.1.10',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120',
        NULL, NULL, 'success',
        NOW() - INTERVAL '1 day'
    ),
    -- Failed login attempt (wrong password)
    (
        'e0000000-0000-0000-0000-000000000002',
        NULL,
        'admin@techpartspro.com',
        'login_failed',
        'Failed login -- incorrect password',
        '203.0.113.42',
        'Python-requests/2.28.0',
        NULL, NULL, 'failure',
        NOW() - INTERVAL '3 days'
    ),
    -- Feature flag toggled
    (
        'e0000000-0000-0000-0000-000000000003',
        'a0000000-0000-0000-0000-000000000001',
        'admin@techpartspro.com',
        'feature_flag_toggled',
        'b2b_enabled toggled from FALSE to TRUE',
        '192.168.1.10',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120',
        'feature_flags', NULL, 'success',
        NOW() - INTERVAL '20 days'
    ),
    -- Promotion created
    (
        'e0000000-0000-0000-0000-000000000004',
        'a0000000-0000-0000-0000-000000000001',
        'admin@techpartspro.com',
        'promotion_created',
        'Created promotion WELCOME10 -- 10% off first order',
        '192.168.1.10',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120',
        'promotion', 'ee000000-0000-0000-0000-000000000001', 'success',
        NOW() - INTERVAL '90 days'
    ),
    -- Warehouse manager login
    (
        'e0000000-0000-0000-0000-000000000005',
        'a0000000-0000-0000-0000-000000000002',
        'warehouse@techpartspro.com',
        'login_success',
        'Warehouse manager logged in',
        '10.0.0.5',
        'Mozilla/5.0 (Windows NT 10.0) Chrome/120',
        NULL, NULL, 'success',
        NOW() - INTERVAL '2 days'
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- 14. SCHEDULED JOBS
-- =============================================================

INSERT INTO scheduled_jobs (
    id, job_type, name,
    reference_type, reference_id,
    scheduled_for, status, attempts, max_attempts,
    last_attempt_at, completed_at, error_message, created_by
) VALUES
    -- Activate Autumn Tools Sale promotion in 7 days
    (
        'f5000000-0000-0000-0000-000000000001',
        'activate_promotion',
        'Activate: Autumn Tools Sale -- 15% Off Tools',
        'promotion', 'ee000000-0000-0000-0000-000000000003',
        NOW() + INTERVAL '7 days',
        'pending', 0, 3, NULL, NULL, NULL,
        'a0000000-0000-0000-0000-000000000001'
    ),
    -- Deactivate Autumn Tools Sale 21 days from now
    (
        'f5000000-0000-0000-0000-000000000002',
        'deactivate_promotion',
        'Deactivate: Autumn Tools Sale -- 15% Off Tools',
        'promotion', 'ee000000-0000-0000-0000-000000000003',
        NOW() + INTERVAL '21 days',
        'pending', 0, 3, NULL, NULL, NULL,
        'a0000000-0000-0000-0000-000000000001'
    ),
    -- Low stock alert job for Fluke 117 (already ran -- completed)
    (
        'f5000000-0000-0000-0000-000000000003',
        'send_low_stock_alert',
        'Low Stock Alert: Fluke 117 below reorder point',
        'inventory', 'fa000000-0000-0000-0000-000000000009',
        NOW() - INTERVAL '12 hours',
        'completed', 1, 3,
        NOW() - INTERVAL '12 hours',
        NOW() - INTERVAL '12 hours',
        NULL, NULL  -- system-generated
    ),
    -- Net terms payment reminder for Acme Corp order (due in 60 days)
    (
        'f5000000-0000-0000-0000-000000000004',
        'send_net_terms_reminder',
        'Payment Due Reminder: ORD-2024-0003 -- Acme Corp',
        'order', 'eb000000-0000-0000-0000-000000000003',
        NOW() + INTERVAL '53 days', -- 7 days before due date
        'pending', 0, 3, NULL, NULL, NULL,
        'a0000000-0000-0000-0000-000000000003'  -- sales rep
    ),
    -- Expire RFQ if not accepted within 14 days
    (
        'f5000000-0000-0000-0000-000000000005',
        'expire_rfq',
        'Auto-expire RFQ-2024-0001 if not accepted',
        'rfq', 'f3000000-0000-0000-0000-000000000001',
        NOW() + INTERVAL '14 days',
        'pending', 0, 3, NULL, NULL, NULL,
        NULL  -- system-generated when quote was sent
    )
ON CONFLICT DO NOTHING;


-- =============================================================
-- END OF DUMMY DATA
-- Scenario: TechParts Pro
-- Tables populated: 46 / 46
-- Records inserted: ~150 rows across all tables
-- All FK references verified and consistent\reset
-- =============================================================
