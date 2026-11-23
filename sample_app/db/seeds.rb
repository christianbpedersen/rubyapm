# Seeds a shop big enough for realistic query plans:
# 2k products, 5k customers, 20k orders, ~60k line items, 30k reviews, 400k page views.
conn = ActiveRecord::Base.connection
if Product.exists? && ENV["FORCE"] != "1"
  puts "Shopwell already has data; not reseeding (FORCE=1 bin/rails db:seed to wipe and reseed)."
  return
end
puts "Seeding…"
conn.execute("TRUNCATE page_views, reviews, line_items, orders, customers, products, categories RESTART IDENTITY CASCADE")
conn.execute(<<~SQL)
  INSERT INTO categories (name, created_at, updated_at)
  SELECT c, now(), now() FROM unnest(ARRAY['Books','Electronics','Garden','Kitchen','Toys','Outdoor','Music','Games','Office','Pets','Beauty','Sports']) c;
  INSERT INTO products (category_id, name, description, price_cents, stock, sku, created_at, updated_at)
  SELECT 1 + (i % 12), 'Product ' || i, repeat('A lovely thing. ', 1 + i % 20), 199 + (i * 37) % 20000, (i * 13) % 200,
         'SKU-' || lpad(i::text, 6, '0'), now(), now()
  FROM generate_series(1, 2000) i;
  INSERT INTO customers (name, email, country, created_at, updated_at)
  SELECT 'Customer ' || i, 'customer' || i || '@example.com', (ARRAY['US','DK','DE','GB','FR'])[1 + i % 5], now(), now()
  FROM generate_series(1, 5000) i;
  INSERT INTO orders (customer_id, status, total_cents, created_at, updated_at)
  SELECT 1 + (i * 7) % 5000, (ARRAY['paid','confirmed','pending','refunded'])[1 + i % 4], 0, now() - (i || ' minutes')::interval, now()
  FROM generate_series(1, 20000) i;
  INSERT INTO line_items (order_id, product_id, quantity, price_cents, created_at, updated_at)
  SELECT 1 + (i % 20000), 1 + (i * 31) % 2000, 1 + i % 3, 199 + (i * 37) % 20000, now(), now()
  FROM generate_series(1, 60000) i;
  INSERT INTO reviews (product_id, customer_id, rating, body, created_at, updated_at)
  SELECT 1 + (i * 17) % 2000, 1 + (i * 11) % 5000, 1 + i % 5, 'Review text ' || i, now(), now()
  FROM generate_series(1, 30000) i;
  INSERT INTO page_views (product_id, customer_id, path, referrer, country, duration_ms, viewed_at)
  SELECT 1 + (i * 13) % 2000, 1 + (i * 3) % 5000,
         CASE WHEN i % 3 = 0 THEN '/products/' || (1 + i % 2000) WHEN i % 3 = 1 THEN '/search' ELSE '/' END,
         (ARRAY['google','newsletter','direct','facebook','partner'])[1 + i % 5], (ARRAY['US','DK','DE','GB','FR'])[1 + i % 5],
         (i * 97) % 9000, now() - ((i % 43200) || ' minutes')::interval
  FROM generate_series(1, 400000) i;
  ANALYZE;
SQL
puts "Products: #{Product.count}, orders: #{Order.count}, page views: #{PageView.count}"
