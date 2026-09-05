CREATE TABLE IF NOT EXISTS bulletins (
    id BIGSERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    state VARCHAR(255) NOT NULL,
    contact VARCHAR(255) NOT NULL,
    price NUMERIC(12, 2) NOT NULL,
    image_key VARCHAR(255),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
