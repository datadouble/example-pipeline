-- Copyright (c) 2026- Tight Line LLC
-- SPDX-License-Identifier: MIT

-- The example source: generated customers, their orders, and products with
-- pgvector embeddings for recommendations.
CREATE EXTENSION vector;
CREATE TABLE customer (id integer PRIMARY KEY, name text NOT NULL, email text NOT NULL);
CREATE TABLE orders (
    id integer PRIMARY KEY, customer_id integer NOT NULL REFERENCES customer, total numeric
);
INSERT INTO customer
    SELECT g, 'Customer ' || g, 'customer' || g || '@shop.example.com'
    FROM generate_series(1, 30) g;
INSERT INTO orders SELECT g, 1 + g % 30, g * 1.5 FROM generate_series(1, 90) g;
CREATE TABLE product (id integer PRIMARY KEY, name text NOT NULL, embedding vector(3));
INSERT INTO product SELECT g, 'Product ' || g, ARRAY[g, g * 2, g * 3]::vector FROM generate_series(1, 5) g;
