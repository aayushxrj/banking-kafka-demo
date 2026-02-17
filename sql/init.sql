CREATE SCHEMA IF NOT EXISTS analytics;

CREATE TABLE IF NOT EXISTS public.accounts (
  account_id SERIAL PRIMARY KEY,
  customer_name TEXT NOT NULL,
  account_type TEXT NOT NULL CHECK (account_type IN ('SAVINGS','CURRENT')),
  balance NUMERIC(14,2) NOT NULL DEFAULT 0,
  opened_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.transactions (
  tx_id BIGSERIAL PRIMARY KEY,
  account_id INT NOT NULL REFERENCES public.accounts(account_id),
  amount NUMERIC(14,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  merchant TEXT,
  channel TEXT CHECK (channel IN ('UPI','CARD','IMPS','NEFT','RTGS','ATM')),
  direction TEXT CHECK (direction IN ('DEBIT','CREDIT')),
  event_time TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Seed customers & a few transactions
INSERT INTO public.accounts (customer_name, account_type, balance)
VALUES ('Asha Rao','SAVINGS',50000.00),
       ('Vikram Singh','CURRENT',250000.00);

INSERT INTO public.transactions (account_id, amount, currency, merchant, channel, direction, event_time)
VALUES (1, -1500.00, 'INR', 'BigBazaar', 'CARD', 'DEBIT', NOW() - INTERVAL '1 day'),
       (1,  20000.00, 'INR', 'Salary',    'NEFT', 'CREDIT', NOW() - INTERVAL '20 hours'),
       (2,  -5000.00, 'INR', 'Amazon',    'CARD', 'DEBIT', NOW() - INTERVAL '2 hours');