-- Activa la ficha de la pieza. Pegue todo en Supabase > SQL Editor y presione Run.
alter table piezas
  add column if not exists descripcion text,
  add column if not exists marca text,
  add column if not exists tipo text,
  add column if not exists proveedor text,
  add column if not exists notas text;
notify pgrst, 'reload schema';
