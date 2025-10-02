-- demo schema you can remove/ignore
CREATE TABLE IF NOT EXISTS demo_hello(id SERIAL PRIMARY KEY, msg TEXT);
INSERT INTO demo_hello(msg) VALUES ('hello from hana-standin');
