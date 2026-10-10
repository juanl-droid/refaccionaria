-- Crea el espacio privado para el catálogo. Pegue todo en Supabase > SQL Editor y presione Run.
insert into storage.buckets (id, name, public) values ('catalogos', 'catalogos', false)
on conflict (id) do nothing;
create policy "leer catalogos con sesion" on storage.objects
  for select to authenticated using (bucket_id = 'catalogos');
