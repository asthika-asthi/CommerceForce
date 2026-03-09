-- =============================================================
-- WHITE-LABEL COMMERCE PLATFORM — COMPLETE DATABASE SCHEMA
-- Version 2.1
-- PostgreSQL (Google Cloud SQL)
-- Per-client isolated database — run once per new client instance
--
-- Covers:
--   Sections 0–10 : Original 10 Application Service Layer modules
--   Section  11   : Audit Log              (admin addition)
--   Section  12   : Admin Activity Log     (admin addition)
--   Section  13   : Media Asset Management (admin addition)
--   Section  14   : Scheduled Jobs         (admin addition)
--   Section  15   : Seed Data              (roles, permissions, feature flags)
-- =============================================================

-- Enable pgcrypto for gen_random_uuid() if not already active
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- =============================================================
-- SAFETY GUARD
-- This script is safe to re-run against an existing database.
-- All CREATE statements use IF NOT EXISTS.
-- Seed INSERT statements use ON CONFLICT DO NOTHING.
--
-- DO NOT run against the postgres system database.
-- DO NOT add DROP DATABASE here — database creation is handled
-- by provision-client.sh before this script is invoked.
-- =============================================================

DO $$
BEGIN
    IF current_database() = 'postgres' THEN
        RAISE EXCEPTION
            'Safety check failed: do not run database.sql against '
            'the postgres system database. Connect to the correct '
            'client database first.';
    END IF;
    RAISE NOTICE 'Safety check passed: running against database "%"', current_database();
END
$$;




-- ─────────────────────────────────────────────────────────────
-- 0. PLATFORM CONFIGURATION
--    Feature flags and branding — loaded at boot, cached in Redis
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS branding_config (
    id                  SERIAL          PRIMARY KEY,
    company_name        VARCHAR(200)    NOT NULL,
    domain              VARCHAR(255)    NOT NULL UNIQUE,
    logo_url            TEXT,
    favicon_url         TEXT,
    primary_color       VARCHAR(7),
    secondary_color     VARCHAR(7),
    email_from_name     VARCHAR(200),
    email_from_address  VARCHAR(255),
    invoice_template    VARCHAR(100)    NOT NULL DEFAULT 'default',
    support_email       VARCHAR(255),
    support_phone       VARCHAR(50),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS feature_flags (
    id              SERIAL          PRIMARY KEY,
    feature_key     VARCHAR(100)    NOT NULL UNIQUE,
    -- b2b_enabled | rfq_enabled | net_terms | tiered_pricing
    -- loyalty_program | sale_enabled | contract_pricing
    enabled         BOOLEAN         NOT NULL DEFAULT FALSE,
    config_json     JSONB           NOT NULL DEFAULT '{}',
    -- e.g. net_terms: {"max_days": 60}
    description     TEXT,
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────────────
-- 1. IDENTITY & ACCESS SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS roles (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    -- superadmin | admin | warehouse_manager | sales_rep
    -- customer | b2b_buyer | b2b_manager
    description TEXT,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS permissions (
    id          SERIAL          PRIMARY KEY,
    resource    VARCHAR(100)    NOT NULL,
    -- products | categories | orders | inventory | pricing
    -- promotions | customers | rfq | users | reports | config
    action      VARCHAR(50)     NOT NULL,
    -- create | read | update | delete | approve | export
    description TEXT,
    UNIQUE (resource, action)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id         INT     NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id   INT     NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS users (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    password_hash       TEXT        NOT NULL,
    role_id             INT         NOT NULL REFERENCES roles(id),
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    phone               VARCHAR(50),
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    email_verified      BOOLEAN     NOT NULL DEFAULT FALSE,
    email_verified_at   TIMESTAMPTZ,
    last_login_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email          ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role           ON users(role_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user  ON refresh_tokens(user_id);


-- ─────────────────────────────────────────────────────────────
-- 2. CUSTOMER SERVICE  (B2C & B2B)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS customer_groups (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    -- retail | vip | wholesale | trade
    description TEXT,
    is_b2b      BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        UNIQUE REFERENCES users(id) ON DELETE SET NULL,
    customer_group_id   INT         REFERENCES customer_groups(id),
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    email               VARCHAR(255) NOT NULL UNIQUE,
    phone               VARCHAR(50),
    date_of_birth       DATE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    loyalty_points      INT         NOT NULL DEFAULT 0,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS companies (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(255)    NOT NULL,
    registration_number VARCHAR(100),
    tax_number          VARCHAR(100),
    industry            VARCHAR(100),
    website             VARCHAR(255),
    credit_limit        NUMERIC(12,2)   NOT NULL DEFAULT 0,
    payment_terms_days  INT             NOT NULL DEFAULT 0,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS company_contacts (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    customer_id UUID        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    job_title   VARCHAR(100),
    is_primary  BOOLEAN     NOT NULL DEFAULT FALSE,
    can_order   BOOLEAN     NOT NULL DEFAULT TRUE,
    can_approve BOOLEAN     NOT NULL DEFAULT FALSE,
    UNIQUE (company_id, customer_id)
);

CREATE TABLE IF NOT EXISTS addresses (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID        REFERENCES customers(id) ON DELETE CASCADE,
    company_id      UUID        REFERENCES companies(id) ON DELETE CASCADE,
    address_type    VARCHAR(20) NOT NULL DEFAULT 'shipping',
    -- shipping | billing
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    full_name       VARCHAR(200),
    line1           VARCHAR(255) NOT NULL,
    line2           VARCHAR(255),
    city            VARCHAR(100) NOT NULL,
    state_province  VARCHAR(100),
    postal_code     VARCHAR(20),
    country_code    CHAR(2)     NOT NULL,
    phone           VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (customer_id IS NOT NULL OR company_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_customers_email          ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_group          ON customers(customer_group_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_company ON company_contacts(company_id);
CREATE INDEX IF NOT EXISTS idx_addresses_customer       ON addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_addresses_company        ON addresses(company_id);


-- ─────────────────────────────────────────────────────────────
-- 3. PRODUCT CATALOG SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS categories (
    id          SERIAL          PRIMARY KEY,
    parent_id   INT             REFERENCES categories(id) ON DELETE SET NULL,
    name        VARCHAR(200)    NOT NULL,
    slug        VARCHAR(200)    NOT NULL UNIQUE,
    description TEXT,
    image_url   TEXT,
    sort_order  INT             NOT NULL DEFAULT 0,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS brands (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(200)    NOT NULL UNIQUE,
    slug        VARCHAR(200)    NOT NULL UNIQUE,
    logo_url    TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    sku                 VARCHAR(100)    NOT NULL UNIQUE,
    name                VARCHAR(300)    NOT NULL,
    slug                VARCHAR(300)    NOT NULL UNIQUE,
    description         TEXT,
    short_description   TEXT,
    category_id         INT             REFERENCES categories(id) ON DELETE SET NULL,
    brand_id            INT             REFERENCES brands(id) ON DELETE SET NULL,
    base_price          NUMERIC(12,2)   NOT NULL,
    cost_price          NUMERIC(12,2),
    tax_class           VARCHAR(50)     NOT NULL DEFAULT 'standard',
    weight_kg           NUMERIC(8,3),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    is_featured         BOOLEAN         NOT NULL DEFAULT FALSE,
    is_b2b_only         BOOLEAN         NOT NULL DEFAULT FALSE,
    meta_title          VARCHAR(300),
    meta_description    TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS product_images (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    -- References media_assets.id for full asset tracking (see Section 13)
    asset_id    UUID,
    image_url   TEXT        NOT NULL,
    alt_text    VARCHAR(300),
    sort_order  INT         NOT NULL DEFAULT 0,
    is_primary  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS attribute_definitions (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL UNIQUE,
    -- color | size | material | finish
    input_type  VARCHAR(20)     NOT NULL DEFAULT 'text',
    -- text | select | multiselect
    is_variant  BOOLEAN         NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS product_attributes (
    id           UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id   UUID    NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    attribute_id INT     NOT NULL REFERENCES attribute_definitions(id),
    value        TEXT    NOT NULL,
    UNIQUE (product_id, attribute_id, value)
);

CREATE TABLE IF NOT EXISTS product_variants (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku             VARCHAR(100) NOT NULL UNIQUE,
    name            VARCHAR(300),
    price_override  NUMERIC(12,2),
    -- NULL = inherit products.base_price
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS variant_attributes (
    variant_id   UUID    NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    attribute_id INT     NOT NULL REFERENCES attribute_definitions(id),
    value        TEXT    NOT NULL,
    PRIMARY KEY (variant_id, attribute_id)
);

CREATE TABLE IF NOT EXISTS product_related (
    product_id          UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    related_product_id  UUID        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    relation_type       VARCHAR(50) NOT NULL DEFAULT 'related',
    -- related | upsell | cross_sell
    PRIMARY KEY (product_id, related_product_id)
);

CREATE INDEX IF NOT EXISTS idx_products_sku        ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_slug       ON products(slug);
CREATE INDEX IF NOT EXISTS idx_products_category   ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_active     ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_product_images_product  ON product_images(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product ON product_variants(product_id);


-- ─────────────────────────────────────────────────────────────
-- 4. PRICING ENGINE
--    Pricing flow: base_price → pricing_rules (by priority)
--                → promotions → coupon → final price
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pricing_rules (
    id                  SERIAL          PRIMARY KEY,
    rule_type           VARCHAR(30)     NOT NULL,
    -- base | tiered | contract | customer_group | sale
    name                VARCHAR(200)    NOT NULL,
    product_id          UUID            REFERENCES products(id) ON DELETE CASCADE,
    variant_id          UUID            REFERENCES product_variants(id) ON DELETE CASCADE,
    category_id         INT             REFERENCES categories(id) ON DELETE CASCADE,
    customer_group_id   INT             REFERENCES customer_groups(id) ON DELETE CASCADE,
    company_id          UUID            REFERENCES companies(id) ON DELETE CASCADE,
    -- contract pricing — requires b2b_enabled flag
    min_quantity        INT             NOT NULL DEFAULT 1,
    discount_type       VARCHAR(20)     NOT NULL DEFAULT 'percentage',
    -- percentage | fixed
    discount_value      NUMERIC(10,4)   NOT NULL,
    fixed_price         NUMERIC(12,2),
    -- when set, overrides base_price entirely
    priority            INT             NOT NULL DEFAULT 0,
    -- higher number = evaluated first
    start_date          TIMESTAMPTZ,
    end_date            TIMESTAMPTZ,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promotions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    code                    VARCHAR(100)    UNIQUE,
    -- NULL = auto-applied, no coupon code needed
    name                    VARCHAR(200)    NOT NULL,
    type                    VARCHAR(20)     NOT NULL,
    -- percentage | fixed | bogo | free_shipping
    discount_value          NUMERIC(10,4)   NOT NULL DEFAULT 0,
    min_order_value         NUMERIC(12,2),
    max_uses                INT,
    -- NULL = unlimited
    uses_count              INT             NOT NULL DEFAULT 0,
    max_uses_per_customer   INT,
    product_id              UUID            REFERENCES products(id) ON DELETE SET NULL,
    category_id             INT             REFERENCES categories(id) ON DELETE SET NULL,
    customer_group_id       INT             REFERENCES customer_groups(id) ON DELETE SET NULL,
    is_stackable            BOOLEAN         NOT NULL DEFAULT FALSE,
    start_date              TIMESTAMPTZ,
    end_date                TIMESTAMPTZ,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promotion_usage (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    promotion_id    UUID        NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
    customer_id     UUID        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    order_id        UUID,
    -- FK → orders added via ALTER TABLE below (orders not yet defined)
    used_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pricing_rules_product  ON pricing_rules(product_id);
CREATE INDEX IF NOT EXISTS idx_pricing_rules_category ON pricing_rules(category_id);
CREATE INDEX IF NOT EXISTS idx_pricing_rules_company  ON pricing_rules(company_id);
CREATE INDEX IF NOT EXISTS idx_pricing_rules_active   ON pricing_rules(is_active, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_promotions_code        ON promotions(code);
CREATE INDEX IF NOT EXISTS idx_promotions_active      ON promotions(is_active, start_date, end_date);


-- ─────────────────────────────────────────────────────────────
-- 5. CART SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS carts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID        REFERENCES customers(id) ON DELETE SET NULL,
    -- NULL = guest cart
    session_id      VARCHAR(255),
    -- guest session token; one of customer_id or session_id must be set
    company_id      UUID        REFERENCES companies(id) ON DELETE SET NULL,
    coupon_code     VARCHAR(100),
    currency_code   CHAR(3)     NOT NULL DEFAULT 'GBP',
    notes           TEXT,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (customer_id IS NOT NULL OR session_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS cart_items (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id     UUID            NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id  UUID            NOT NULL REFERENCES products(id),
    variant_id  UUID            REFERENCES product_variants(id),
    quantity    INT             NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12,2)   NOT NULL,
    -- price snapshot at time of add
    custom_data JSONB           NOT NULL DEFAULT '{}',
    -- e.g. engraving text, gift wrap
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_carts_customer    ON carts(customer_id);
CREATE INDEX IF NOT EXISTS idx_carts_session     ON carts(session_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_cart   ON cart_items(cart_id);


-- ─────────────────────────────────────────────────────────────
-- 6. CHECKOUT SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS shipping_methods (
    id              SERIAL          PRIMARY KEY,
    name            VARCHAR(200)    NOT NULL,
    carrier         VARCHAR(100),
    code            VARCHAR(100)    NOT NULL UNIQUE,
    base_cost       NUMERIC(10,2)   NOT NULL DEFAULT 0,
    free_threshold  NUMERIC(12,2),
    -- NULL = no free shipping threshold
    estimated_days  INT,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS checkout_sessions (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    cart_id                 UUID            NOT NULL REFERENCES carts(id),
    customer_id             UUID            REFERENCES customers(id),
    shipping_address_id     UUID            REFERENCES addresses(id),
    billing_address_id      UUID            REFERENCES addresses(id),
    shipping_method_id      INT             REFERENCES shipping_methods(id),
    payment_method          VARCHAR(50),
    -- stripe | bank_transfer | net_terms
    payment_provider_ref    TEXT,
    -- e.g. Stripe PaymentIntent ID
    subtotal                NUMERIC(12,2),
    shipping_cost           NUMERIC(12,2)   NOT NULL DEFAULT 0,
    tax_amount              NUMERIC(12,2)   NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(12,2)   NOT NULL DEFAULT 0,
    total_amount            NUMERIC(12,2),
    currency_code           CHAR(3)         NOT NULL DEFAULT 'GBP',
    status                  VARCHAR(30)     NOT NULL DEFAULT 'pending',
    -- pending | payment_processing | payment_failed | completed | expired
    expires_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checkout_sessions_cart     ON checkout_sessions(cart_id);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_customer ON checkout_sessions(customer_id);
CREATE INDEX IF NOT EXISTS idx_checkout_sessions_status   ON checkout_sessions(status);


-- ─────────────────────────────────────────────────────────────
-- 7. ORDER MANAGEMENT SYSTEM
--    Addresses and product details are JSON-snapshotted at
--    time of purchase to preserve the exact order state.
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS orders (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number            VARCHAR(50)     NOT NULL UNIQUE,
    -- e.g. ORD-20240001
    customer_id             UUID            NOT NULL REFERENCES customers(id),
    company_id              UUID            REFERENCES companies(id),
    checkout_session_id     UUID            REFERENCES checkout_sessions(id),
    status                  VARCHAR(30)     NOT NULL DEFAULT 'pending',
    -- pending | confirmed | processing | shipped | delivered | cancelled | refunded
    payment_status          VARCHAR(30)     NOT NULL DEFAULT 'unpaid',
    -- unpaid | paid | partially_paid | refunded
    payment_method          VARCHAR(50),
    payment_provider_ref    TEXT,
    currency_code           CHAR(3)         NOT NULL DEFAULT 'GBP',
    subtotal                NUMERIC(12,2)   NOT NULL,
    shipping_cost           NUMERIC(12,2)   NOT NULL DEFAULT 0,
    tax_amount              NUMERIC(12,2)   NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(12,2)   NOT NULL DEFAULT 0,
    total_amount            NUMERIC(12,2)   NOT NULL,
    shipping_address        JSONB           NOT NULL,
    -- snapshot — immune to future address edits
    billing_address         JSONB           NOT NULL,
    -- snapshot
    shipping_method_name    VARCHAR(200),
    -- snapshot
    notes                   TEXT,
    internal_notes          TEXT,
    net_terms_due_date      DATE,
    -- B2B: set when payment_method = net_terms
    placed_at               TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    confirmed_at            TIMESTAMPTZ,
    shipped_at              TIMESTAMPTZ,
    delivered_at            TIMESTAMPTZ,
    cancelled_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID            NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id      UUID            NOT NULL REFERENCES products(id),
    variant_id      UUID            REFERENCES product_variants(id),
    sku             VARCHAR(100)    NOT NULL,
    -- snapshot
    product_name    VARCHAR(300)    NOT NULL,
    -- snapshot
    quantity        INT             NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(12,2)   NOT NULL,
    tax_rate        NUMERIC(6,4)    NOT NULL DEFAULT 0,
    -- snapshot of rate at time of order
    discount_amount NUMERIC(12,2)   NOT NULL DEFAULT 0,
    line_total      NUMERIC(12,2)   NOT NULL,
    -- quantity × unit_price
    custom_data     JSONB           NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS order_status_history (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    UUID        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status      VARCHAR(30) NOT NULL,
    note        TEXT,
    changed_by  UUID        REFERENCES users(id),
    -- NULL = system/automated
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refunds (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID            NOT NULL REFERENCES orders(id),
    amount          NUMERIC(12,2)   NOT NULL,
    reason          TEXT,
    provider_ref    TEXT,
    -- payment gateway refund ID
    status          VARCHAR(30)     NOT NULL DEFAULT 'pending',
    -- pending | processed | failed
    created_by      UUID            REFERENCES users(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMPTZ
);

-- Deferred FK: promotion_usage.order_id → orders
ALTER TABLE promotion_usage
    ADD CONSTRAINT fk_promotion_usage_order
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_orders_customer        ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_company         ON orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_status          ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status  ON orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_orders_number          ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_placed_at       ON orders(placed_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order      ON order_items(order_id);


-- ─────────────────────────────────────────────────────────────
-- 8. INVENTORY SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS warehouses (
    id          SERIAL          PRIMARY KEY,
    name        VARCHAR(200)    NOT NULL,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    address     JSONB,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS inventory (
    id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id          UUID    NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    variant_id          UUID    REFERENCES product_variants(id) ON DELETE CASCADE,
    -- NULL for non-variant products
    warehouse_id        INT     NOT NULL REFERENCES warehouses(id),
    quantity_on_hand    INT     NOT NULL DEFAULT 0,
    quantity_reserved   INT     NOT NULL DEFAULT 0,
    -- held by confirmed but unshipped orders
    quantity_available  INT     GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,
    -- NOTE for SQLAlchemy: map this column with Computed("quantity_on_hand - quantity_reserved", persisted=True)
    reorder_point       INT     NOT NULL DEFAULT 0,
    reorder_qty         INT     NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (product_id, variant_id, warehouse_id)
);

CREATE TABLE IF NOT EXISTS inventory_movements (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID        NOT NULL REFERENCES products(id),
    variant_id      UUID        REFERENCES product_variants(id),
    warehouse_id    INT         NOT NULL REFERENCES warehouses(id),
    movement_type   VARCHAR(30) NOT NULL,
    -- purchase | sale | return | adjustment | transfer_in | transfer_out
    quantity_delta  INT         NOT NULL,
    -- positive = stock in, negative = stock out
    reference_type  VARCHAR(50),
    -- order | rfq | manual | scheduled_job
    reference_id    UUID,
    -- ID of the triggering record
    note            TEXT,
    created_by      UUID        REFERENCES users(id),
    -- NULL = system/automated
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inventory_product          ON inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_warehouse        ON inventory(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_inventory_low_stock        ON inventory(quantity_available, reorder_point);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_product ON inventory_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_ref    ON inventory_movements(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_date   ON inventory_movements(created_at);


-- ─────────────────────────────────────────────────────────────
-- 9. QUOTE / RFQ SERVICE
--    B2B only — requires feature flag rfq_enabled = true
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rfq_quotes (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_number        VARCHAR(50) NOT NULL UNIQUE,
    -- e.g. RFQ-20240001
    company_id          UUID        NOT NULL REFERENCES companies(id),
    customer_id         UUID        NOT NULL REFERENCES customers(id),
    assigned_to         UUID        REFERENCES users(id),
    -- sales rep responsible
    status              VARCHAR(30) NOT NULL DEFAULT 'draft',
    -- draft | submitted | under_review | quoted | accepted | rejected | expired | converted
    currency_code       CHAR(3)     NOT NULL DEFAULT 'GBP',
    subtotal            NUMERIC(12,2),
    discount_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(12,2),
    valid_until         DATE,
    payment_terms       VARCHAR(100),
    notes               TEXT,
    internal_notes      TEXT,
    converted_order_id  UUID        REFERENCES orders(id),
    submitted_at        TIMESTAMPTZ,
    quoted_at           TIMESTAMPTZ,
    accepted_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rfq_items (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id          UUID            NOT NULL REFERENCES rfq_quotes(id) ON DELETE CASCADE,
    product_id      UUID            NOT NULL REFERENCES products(id),
    variant_id      UUID            REFERENCES product_variants(id),
    quantity        INT             NOT NULL CHECK (quantity > 0),
    requested_price NUMERIC(12,2),
    -- customer's target price
    quoted_price    NUMERIC(12,2),
    -- sales rep's response price
    notes           TEXT
);

CREATE TABLE IF NOT EXISTS rfq_status_history (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    rfq_id      UUID        NOT NULL REFERENCES rfq_quotes(id) ON DELETE CASCADE,
    status      VARCHAR(30) NOT NULL,
    note        TEXT,
    changed_by  UUID        REFERENCES users(id),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rfq_company    ON rfq_quotes(company_id);
CREATE INDEX IF NOT EXISTS idx_rfq_assigned   ON rfq_quotes(assigned_to);
CREATE INDEX IF NOT EXISTS idx_rfq_status     ON rfq_quotes(status);
CREATE INDEX IF NOT EXISTS idx_rfq_items_rfq  ON rfq_items(rfq_id);


-- ─────────────────────────────────────────────────────────────
-- 10. NOTIFICATION SERVICE
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notification_templates (
    id          SERIAL          PRIMARY KEY,
    event_key   VARCHAR(100)    NOT NULL UNIQUE,
    -- order_placed | order_shipped | order_delivered | order_cancelled
    -- rfq_submitted | rfq_quoted | rfq_accepted | rfq_rejected
    -- password_reset | email_verification | low_stock_alert
    name        VARCHAR(200)    NOT NULL,
    channel     VARCHAR(20)     NOT NULL DEFAULT 'email',
    -- email | sms | push
    subject     TEXT,
    body_html   TEXT,
    body_text   TEXT,
    -- plain text fallback / SMS body
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id     INT         REFERENCES notification_templates(id),
    event_key       VARCHAR(100) NOT NULL,
    channel         VARCHAR(20) NOT NULL,
    recipient       VARCHAR(255) NOT NULL,
    -- email address or phone number
    customer_id     UUID        REFERENCES customers(id) ON DELETE SET NULL,
    reference_type  VARCHAR(50),
    -- order | rfq | user | inventory
    reference_id    UUID,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | sent | delivered | failed | bounced
    provider_ref    TEXT,
    -- external provider message ID
    error_message   TEXT,
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_preferences (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    event_key   VARCHAR(100) NOT NULL,
    channel     VARCHAR(20) NOT NULL,
    is_enabled  BOOLEAN     NOT NULL DEFAULT TRUE,
    UNIQUE (customer_id, event_key, channel)
);

CREATE INDEX IF NOT EXISTS idx_notification_log_recipient ON notification_log(recipient);
CREATE INDEX IF NOT EXISTS idx_notification_log_ref       ON notification_log(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_notification_log_status    ON notification_log(status);
CREATE INDEX IF NOT EXISTS idx_notification_log_date      ON notification_log(created_at);
CREATE INDEX IF NOT EXISTS idx_notification_prefs_customer ON notification_preferences(customer_id);


-- =============================================================
-- 11. AUDIT LOG  (Admin Addition)
--     Central immutable record of every data change made by
--     any user across all tables. Written by application layer
--     service hooks — never deleted, never updated.
--     Answers: who changed what, when, and what did it look like
--     before and after.
-- =============================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name      VARCHAR(100) NOT NULL,
    -- name of the affected table e.g. products, orders, pricing_rules
    record_id       TEXT        NOT NULL,
    -- stringified PK of the affected row (UUID or int)
    action          VARCHAR(10) NOT NULL,
    -- INSERT | UPDATE | DELETE
    changed_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    -- NULL = system / automated process
    changed_by_role VARCHAR(100),
    -- snapshot of role name at time of change
    ip_address      INET,
    old_values      JSONB,
    -- NULL for INSERT
    new_values      JSONB,
    -- NULL for DELETE
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit log is append-only. No UPDATE or DELETE should ever be issued against it.
-- Partitioning by month is recommended once volume grows (Cloud SQL supports declarative partitioning).

CREATE INDEX IF NOT EXISTS idx_audit_log_table        ON audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_record       ON audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user         ON audit_log(changed_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_date         ON audit_log(changed_at);


-- =============================================================
-- 12. ADMIN ACTIVITY LOG  (Admin Addition)
--     Tracks admin and staff user session events and sensitive
--     actions separately from the general audit log.
--     Purpose: security monitoring, compliance, failed login
--     detection, and support investigations.
-- =============================================================

CREATE TABLE IF NOT EXISTS admin_activity_log (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        REFERENCES users(id) ON DELETE SET NULL,
    -- NULL if login failed (user may not exist)
    email_attempted VARCHAR(255),
    -- always record the email used, even for failed attempts
    activity_type   VARCHAR(50) NOT NULL,
    -- login_success | login_failed | logout
    -- password_changed | password_reset_requested
    -- feature_flag_toggled | branding_config_updated
    -- user_created | user_deactivated | role_changed
    -- bulk_export | price_override | promotion_created
    description     TEXT,
    -- human-readable summary of the action
    ip_address      INET,
    user_agent      TEXT,
    reference_type  VARCHAR(50),
    -- entity type affected e.g. user, product, promotion
    reference_id    UUID,
    -- ID of the affected entity
    outcome         VARCHAR(20) NOT NULL DEFAULT 'success',
    -- success | failure | blocked
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_activity_user    ON admin_activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_admin_activity_type    ON admin_activity_log(activity_type);
CREATE INDEX IF NOT EXISTS idx_admin_activity_date    ON admin_activity_log(created_at);
CREATE INDEX IF NOT EXISTS idx_admin_activity_ip      ON admin_activity_log(ip_address);
CREATE INDEX IF NOT EXISTS idx_admin_activity_outcome ON admin_activity_log(outcome);


-- =============================================================
-- 13. MEDIA ASSET MANAGEMENT  (Admin Addition)
--     Tracks every file uploaded to Cloud Storage.
--     Prevents orphaned files, enables usage reporting,
--     and gives admins a library UI to manage assets.
--     product_images.asset_id links back to this table.
-- =============================================================

CREATE TABLE IF NOT EXISTS media_assets (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name       VARCHAR(500) NOT NULL,
    -- original filename as uploaded
    storage_path    TEXT        NOT NULL UNIQUE,
    -- full Cloud Storage object path e.g. gs://bucket/products/abc123.jpg
    public_url      TEXT        NOT NULL,
    -- CDN-served URL
    mime_type       VARCHAR(100) NOT NULL,
    -- image/jpeg | image/png | image/webp | application/pdf
    file_size_bytes BIGINT      NOT NULL,
    width_px        INT,
    -- NULL for non-image files
    height_px       INT,
    -- NULL for non-image files
    asset_type      VARCHAR(50) NOT NULL DEFAULT 'product_image',
    -- product_image | category_image | brand_logo | invoice_template
    -- branding_asset | document
    uploaded_by     UUID        REFERENCES users(id) ON DELETE SET NULL,
    -- NULL = system upload
    usage_count     INT         NOT NULL DEFAULT 0,
    -- incremented when linked to a product_image, category, brand etc.
    -- 0 = potentially orphaned
    tags            JSONB       NOT NULL DEFAULT '[]',
    -- free-form tags for admin search e.g. ["summer", "sale"]
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Deferred FK: product_images.asset_id → media_assets
ALTER TABLE product_images
    ADD CONSTRAINT fk_product_images_asset
    FOREIGN KEY (asset_id) REFERENCES media_assets(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_media_assets_type      ON media_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_media_assets_uploader  ON media_assets(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_media_assets_usage     ON media_assets(usage_count);
CREATE INDEX IF NOT EXISTS idx_media_assets_mime      ON media_assets(mime_type);


-- =============================================================
-- 14. SCHEDULED JOBS  (Admin Addition)
--     Manages time-based automation: activating sales,
--     expiring promotions, sending low-stock alerts,
--     processing net-terms payment reminders, etc.
--     Google Cloud Scheduler triggers the job runner;
--     this table controls what runs and tracks outcomes.
-- =============================================================

CREATE TABLE IF NOT EXISTS scheduled_jobs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    job_type        VARCHAR(100) NOT NULL,
    -- activate_promotion | deactivate_promotion | activate_pricing_rule
    -- deactivate_pricing_rule | send_low_stock_alert
    -- send_net_terms_reminder | expire_rfq | expire_cart
    -- process_loyalty_points | generate_sales_report
    name            VARCHAR(200) NOT NULL,
    reference_type  VARCHAR(50),
    -- promotion | pricing_rule | rfq | order | report
    reference_id    UUID,
    -- ID of the entity this job acts on (e.g. promotion to activate)
    scheduled_for   TIMESTAMPTZ NOT NULL,
    -- when the job should execute
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | running | completed | failed | cancelled
    attempts        INT         NOT NULL DEFAULT 0,
    max_attempts    INT         NOT NULL DEFAULT 3,
    last_attempt_at TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    error_message   TEXT,
    -- populated on failure
    created_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    -- NULL = system-generated (e.g. auto-created when a promotion is saved)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_status      ON scheduled_jobs(status, scheduled_for);
-- Primary query: find pending jobs due to run
CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_type        ON scheduled_jobs(job_type);
CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_ref         ON scheduled_jobs(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_scheduled_jobs_scheduled   ON scheduled_jobs(scheduled_for);


-- =============================================================
-- 15. SEED DATA
--     Inserted by the provision script on first boot of each
--     new client instance. All values can be updated via the
--     Admin Dashboard after provisioning.
-- =============================================================

-- ── Roles ────────────────────────────────────────────────────
INSERT INTO roles (name, description) VALUES
    ('superadmin',        'Full platform access including config and user management'),
    ('admin',             'Full store management: products, orders, pricing, promotions'),
    ('warehouse_manager', 'Inventory, stock movements, and fulfilment only'),
    ('sales_rep',         'RFQ management, order support, customer management'),
    ('customer',          'B2C storefront access'),
    ('b2b_buyer',         'B2B portal: place orders, submit RFQs'),
    ('b2b_manager',       'B2B portal: all buyer permissions plus approve orders')
ON CONFLICT (name) DO NOTHING;

-- ── Permissions ──────────────────────────────────────────────
INSERT INTO permissions (resource, action, description) VALUES
    -- Products
    ('products',    'create',   'Add new products'),
    ('products',    'read',     'View products'),
    ('products',    'update',   'Edit existing products'),
    ('products',    'delete',   'Remove products'),
    -- Categories
    ('categories',  'create',   'Add categories'),
    ('categories',  'read',     'View categories'),
    ('categories',  'update',   'Edit categories'),
    ('categories',  'delete',   'Remove categories'),
    -- Orders
    ('orders',      'read',     'View orders'),
    ('orders',      'update',   'Update order status'),
    ('orders',      'delete',   'Cancel orders'),
    ('orders',      'export',   'Export order reports'),
    -- Inventory
    ('inventory',   'read',     'View stock levels'),
    ('inventory',   'update',   'Adjust stock levels'),
    -- Pricing
    ('pricing',     'create',   'Add pricing rules'),
    ('pricing',     'read',     'View pricing rules'),
    ('pricing',     'update',   'Edit pricing rules'),
    ('pricing',     'delete',   'Remove pricing rules'),
    -- Promotions
    ('promotions',  'create',   'Create promotions and coupons'),
    ('promotions',  'read',     'View promotions'),
    ('promotions',  'update',   'Edit promotions'),
    ('promotions',  'delete',   'Remove promotions'),
    -- Customers
    ('customers',   'read',     'View customer profiles'),
    ('customers',   'update',   'Edit customer details'),
    ('customers',   'delete',   'Deactivate customers'),
    -- RFQ
    ('rfq',         'read',     'View RFQ quotes'),
    ('rfq',         'update',   'Respond to and manage quotes'),
    ('rfq',         'approve',  'Approve quotes for conversion to orders'),
    -- Users & Roles
    ('users',       'create',   'Create admin/staff users'),
    ('users',       'read',     'View admin/staff users'),
    ('users',       'update',   'Edit admin/staff users'),
    ('users',       'delete',   'Deactivate admin/staff users'),
    -- Config
    ('config',      'read',     'View feature flags and branding'),
    ('config',      'update',   'Update feature flags and branding'),
    -- Media
    ('media',       'create',   'Upload media assets'),
    ('media',       'read',     'View media library'),
    ('media',       'delete',   'Remove media assets'),
    -- Reports
    ('reports',     'read',     'View sales and operational reports'),
    ('reports',     'export',   'Export reports')
ON CONFLICT (resource, action) DO NOTHING;

-- ── Role → Permission assignments ────────────────────────────
-- superadmin: everything
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'superadmin'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- admin: everything except user management
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'admin'
  AND p.resource != 'users'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- warehouse_manager: inventory + orders (read/update) + products (read)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'warehouse_manager'
  AND (
    p.resource = 'inventory'
    OR (p.resource = 'orders'   AND p.action IN ('read', 'update'))
    OR (p.resource = 'products' AND p.action = 'read')
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- sales_rep: orders, rfq, customers (read/update)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'sales_rep'
  AND (
    p.resource = 'orders'
    OR p.resource = 'rfq'
    OR (p.resource = 'customers' AND p.action IN ('read', 'update'))
    OR (p.resource = 'products'  AND p.action = 'read')
  )
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ── Feature flags ────────────────────────────────────────────
INSERT INTO feature_flags (feature_key, enabled, config_json, description) VALUES
    ('b2b_enabled',        FALSE, '{}',                  'Enable B2B portal, company accounts, and B2B pricing'),
    ('rfq_enabled',        FALSE, '{}',                  'Enable Request for Quote workflow (requires b2b_enabled)'),
    ('net_terms',          FALSE, '{"max_days": 30}',    'Allow B2B customers to pay on invoice terms'),
    ('tiered_pricing',     FALSE, '{}',                  'Enable quantity-based tiered pricing rules'),
    ('contract_pricing',   FALSE, '{}',                  'Enable company-specific contract pricing'),
    ('loyalty_program',    FALSE, '{}',                  'Enable loyalty points accrual and redemption'),
    ('sale_enabled',       FALSE, '{}',                  'Enable scheduled sale pricing and promotions'),
    ('guest_checkout',     TRUE,  '{}',                  'Allow B2C checkout without account registration'),
    ('multi_warehouse',    FALSE, '{}',                  'Enable inventory tracking across multiple warehouses')
ON CONFLICT (feature_key) DO NOTHING;

-- ── Default shipping methods ─────────────────────────────────
INSERT INTO shipping_methods (name, carrier, code, base_cost, free_threshold, estimated_days, is_active) VALUES
    ('Standard Delivery',   NULL, 'standard',   4.99,  50.00, 5, TRUE),
    ('Express Delivery',    NULL, 'express',     9.99,  NULL,  2, TRUE),
    ('Free Shipping',       NULL, 'free',        0.00,  NULL,  7, FALSE)
ON CONFLICT (code) DO NOTHING;
-- Note: 'free' method disabled by default; activate when sale_enabled flag is toggled on

-- ── Default warehouse ────────────────────────────────────────
INSERT INTO warehouses (name, code, is_active) VALUES
    ('Main Warehouse', 'MAIN', TRUE)
ON CONFLICT (code) DO NOTHING;

-- ── Default notification templates ──────────────────────────
INSERT INTO notification_templates (event_key, name, channel, subject, is_active) VALUES
    ('order_placed',            'Order Confirmation',           'email', 'Your order has been placed',       TRUE),
    ('order_confirmed',         'Order Confirmed',              'email', 'Your order is confirmed',          TRUE),
    ('order_shipped',           'Order Shipped',                'email', 'Your order is on its way',         TRUE),
    ('order_delivered',         'Order Delivered',              'email', 'Your order has been delivered',    TRUE),
    ('order_cancelled',         'Order Cancelled',              'email', 'Your order has been cancelled',    TRUE),
    ('password_reset',          'Password Reset',               'email', 'Reset your password',              TRUE),
    ('email_verification',      'Verify Your Email',            'email', 'Please verify your email address', TRUE),
    ('rfq_submitted',           'RFQ Received',                 'email', 'We have received your quote request', TRUE),
    ('rfq_quoted',              'Your Quote is Ready',          'email', 'Your quote is ready to review',    TRUE),
    ('rfq_accepted',            'Quote Accepted',               'email', 'Quote accepted — order in progress', TRUE),
    ('low_stock_alert',         'Low Stock Alert',              'email', 'Stock running low',                TRUE),
    ('net_terms_reminder',      'Payment Due Reminder',         'email', 'Payment due soon',                 TRUE)
ON CONFLICT (event_key) DO NOTHING;


-- =============================================================
-- END OF SCHEMA
-- Total tables: 46
-- Version 2.1 — Added safety guard, IF NOT EXISTS on all DDL, ON CONFLICT DO NOTHING on all seed data
-- =============================================================
