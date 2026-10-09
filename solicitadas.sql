-- Activa la lista de piezas solicitadas. Pegue todo en Supabase > SQL Editor y presione Run.
create table if not exists solicitadas (
  id bigint generated always as identity primary key,
  parte text not null,
  cantidad integer not null default 1 check (cantidad > 0),
  nota text,
  usuario uuid references auth.users,
  fecha timestamptz not null default now(),
  surtida boolean not null default false
);
alter table solicitadas enable row level security;
create policy "ver solicitadas" on solicitadas for select to authenticated using (true);
create policy "crear solicitadas" on solicitadas for insert to authenticated with check (usuario = auth.uid());
create policy "marcar solicitadas" on solicitadas for update to authenticated using (true) with check (true);
