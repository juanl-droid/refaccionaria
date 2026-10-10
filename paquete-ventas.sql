-- JMR Inventario: paquete completo (ficha, solicitadas, catálogo privado, ventas,
-- clientes y crédito, entradas de mercancía, reportes y pedidos de mecánicos).
-- Pegue TODO en Supabase > SQL Editor y presione Run. Se puede correr más de una vez.

-- ===== Ajustes a lo que ya existe =====
alter table perfiles add column if not exists rol text not null default 'empleado';
alter table perfiles drop constraint if exists perfiles_rol_check;
alter table perfiles add constraint perfiles_rol_check check (rol in ('empleado','mecanico'));
alter table piezas
  add column if not exists descripcion text, add column if not exists marca text,
  add column if not exists tipo text, add column if not exists proveedor text,
  add column if not exists notas text, add column if not exists minimo integer not null default 0;

-- Todo usuario existente queda con perfil de empleado si aún no lo tenía.
insert into perfiles (id, nombre) select u.id, split_part(u.email, '@', 1) from auth.users u on conflict (id) do nothing;

create or replace function es_personal() returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from perfiles where id = auth.uid() and rol <> 'mecanico') $$;
create or replace function ve_precios() returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from perfiles where id = auth.uid() and puede_precios) $$;

-- ===== Tablas nuevas =====
create table if not exists solicitadas (
  id bigint generated always as identity primary key, parte text not null,
  cantidad integer not null default 1 check (cantidad > 0), nota text,
  usuario uuid references auth.users, fecha timestamptz not null default now(),
  surtida boolean not null default false);
create table if not exists config (clave text primary key, valor text);
insert into config (clave, valor) values
  ('negocio','JMR Refacciones & Servicios Automotrices'), ('direccion',''), ('telefono',''),
  ('pie_ticket','Gracias por su compra. Este ticket no es comprobante fiscal.')
on conflict (clave) do nothing;
create table if not exists clientes (
  id bigint generated always as identity primary key, nombre text not null, telefono text, notas text,
  usuario uuid unique references auth.users on delete set null, creado timestamptz not null default now());
create table if not exists ventas (
  id bigint generated always as identity primary key, fecha timestamptz not null default now(),
  usuario uuid references auth.users, cliente bigint references clientes, cliente_nombre text,
  tipo text not null default 'contado' check (tipo in ('contado','credito')),
  total numeric(12,2) not null default 0, pagado numeric(12,2) not null default 0,
  estado text not null default 'cerrada' check (estado in ('cerrada','cancelada')), nota text);
create index if not exists ventas_fecha on ventas (fecha);
create table if not exists venta_items (
  id bigint generated always as identity primary key, venta bigint not null references ventas on delete cascade,
  parte text not null, descripcion text, cantidad integer not null check (cantidad > 0),
  precio numeric(12,2) not null check (precio >= 0), precio_manual boolean not null default false,
  faltante integer not null default 0);
create index if not exists venta_items_venta on venta_items (venta);
create table if not exists venta_costos (item bigint primary key references venta_items on delete cascade, costo numeric(12,2));
create table if not exists abonos (
  id bigint generated always as identity primary key, cliente bigint not null references clientes,
  monto numeric(12,2) not null check (monto > 0), fecha timestamptz not null default now(),
  usuario uuid references auth.users, nota text);
create table if not exists entradas (
  id bigint generated always as identity primary key, fecha timestamptz not null default now(),
  proveedor text, factura text, usuario uuid references auth.users, total numeric(12,2) not null default 0, nota text);
create table if not exists entrada_items (
  id bigint generated always as identity primary key, entrada bigint not null references entradas on delete cascade,
  parte text not null, cantidad integer not null check (cantidad > 0), costo numeric(12,2));
create table if not exists pedidos (
  id bigint generated always as identity primary key, fecha timestamptz not null default now(),
  cliente bigint references clientes, creado_por uuid references auth.users,
  estado text not null default 'nuevo' check (estado in ('nuevo','confirmado','surtido','cancelado')),
  nota text, respuesta text, venta bigint references ventas);
create table if not exists pedido_items (
  id bigint generated always as identity primary key, pedido bigint not null references pedidos on delete cascade,
  parte text not null, descripcion text, cantidad integer not null check (cantidad > 0));

-- ===== Permisos por tabla =====
alter table solicitadas enable row level security; alter table config enable row level security;
alter table clientes enable row level security; alter table ventas enable row level security;
alter table venta_items enable row level security; alter table venta_costos enable row level security;
alter table abonos enable row level security; alter table entradas enable row level security;
alter table entrada_items enable row level security; alter table pedidos enable row level security;
alter table pedido_items enable row level security;

drop policy if exists "crear piezas" on piezas;
create policy "crear piezas" on piezas for insert to authenticated with check (es_personal());
drop policy if exists "corregir piezas" on piezas;
create policy "corregir piezas" on piezas for update to authenticated using (es_personal()) with check (es_personal());
drop policy if exists "ver movimientos" on movimientos;
create policy "ver movimientos" on movimientos for select to authenticated using (es_personal());
drop policy if exists "crear movimientos" on movimientos;
create policy "crear movimientos" on movimientos for insert to authenticated with check (es_personal() and usuario = auth.uid());

drop policy if exists "ver solicitadas" on solicitadas; drop policy if exists "crear solicitadas" on solicitadas; drop policy if exists "marcar solicitadas" on solicitadas;
create policy "ver solicitadas" on solicitadas for select to authenticated using (es_personal());
create policy "crear solicitadas" on solicitadas for insert to authenticated with check (es_personal() and usuario = auth.uid());
create policy "marcar solicitadas" on solicitadas for update to authenticated using (es_personal()) with check (es_personal());

drop policy if exists "ver config" on config; drop policy if exists "cambiar config" on config;
create policy "ver config" on config for select to authenticated using (true);
create policy "cambiar config" on config for all to authenticated using (ve_precios()) with check (ve_precios());

drop policy if exists "personal clientes" on clientes; drop policy if exists "mi cliente" on clientes;
create policy "personal clientes" on clientes for all to authenticated using (es_personal()) with check (es_personal());
create policy "mi cliente" on clientes for select to authenticated using (usuario = auth.uid());

drop policy if exists "ver ventas" on ventas; create policy "ver ventas" on ventas for select to authenticated using (es_personal());
drop policy if exists "ver venta_items" on venta_items; create policy "ver venta_items" on venta_items for select to authenticated using (es_personal());
drop policy if exists "ver costos" on venta_costos; create policy "ver costos" on venta_costos for select to authenticated using (ve_precios());
drop policy if exists "ver abonos" on abonos; create policy "ver abonos" on abonos for select to authenticated using (es_personal());
drop policy if exists "ver entradas" on entradas; create policy "ver entradas" on entradas for select to authenticated using (es_personal());
drop policy if exists "ver entrada_items" on entrada_items; create policy "ver entrada_items" on entrada_items for select to authenticated using (es_personal());

drop policy if exists "ver pedidos" on pedidos; drop policy if exists "atender pedidos" on pedidos;
create policy "ver pedidos" on pedidos for select to authenticated using (es_personal() or creado_por = auth.uid());
create policy "atender pedidos" on pedidos for update to authenticated using (es_personal()) with check (es_personal());
drop policy if exists "ver pedido_items" on pedido_items;
create policy "ver pedido_items" on pedido_items for select to authenticated
  using (exists (select 1 from pedidos p where p.id = pedido and (es_personal() or p.creado_por = auth.uid())));

-- ===== Operaciones (todo o nada) =====
create or replace function precios_venta(p_partes text[]) returns table (parte text, precio numeric)
language sql stable security definer set search_path = public as
$$ select p.parte, p.precio from precios p where es_personal() and p.parte = any (p_partes) $$;

create or replace function registrar_venta(p_items jsonb, p_cliente bigint default null, p_cliente_nombre text default null,
  p_tipo text default 'contado', p_pagado numeric default null, p_nota text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_item bigint; it jsonb; v_parte text; v_cant int; v_precio numeric; v_lista numeric; v_costo numeric;
  v_exist int; v_anaq text; v_desc text; v_manual boolean; v_total numeric := 0; v_nombre text;
begin
  if not es_personal() then raise exception 'Su usuario no tiene permiso para vender.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'La venta no tiene piezas.'; end if;
  if p_tipo not in ('contado','credito') then raise exception 'Tipo de venta no válido.'; end if;
  if p_tipo = 'credito' and p_cliente is null then raise exception 'La venta a crédito necesita un cliente.'; end if;
  if p_cliente is not null then select nombre into v_nombre from clientes where id = p_cliente;
    if not found then raise exception 'El cliente no existe.'; end if; end if;
  insert into ventas (usuario, cliente, cliente_nombre, tipo, nota)
    values (auth.uid(), p_cliente, coalesce(v_nombre, nullif(trim(p_cliente_nombre),'')), p_tipo, nullif(trim(p_nota),'')) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    v_parte := upper(regexp_replace(coalesce(it->>'parte',''), '\s', '', 'g'));
    v_cant := (it->>'cantidad')::int;
    if v_parte = '' then raise exception 'Hay una pieza sin número de parte.'; end if;
    if v_cant is null or v_cant < 1 then raise exception 'Cantidad no válida en %.', v_parte; end if;
    select cantidad, anaquel, descripcion into v_exist, v_anaq, v_desc from piezas where parte = v_parte for update;
    if not found then
      v_exist := 0; v_anaq := 'SIN-UBICAR'; v_desc := nullif(trim(it->>'descripcion'),'');
      insert into piezas (parte, cantidad, anaquel, capturo, descripcion) values (v_parte, 0, v_anaq, auth.uid(), v_desc);
    end if;
    v_lista := null; v_costo := null;
    select precio, costo into v_lista, v_costo from precios where parte = v_parte;
    if v_lista is not null then v_precio := v_lista; v_manual := false;
    else v_precio := (it->>'precio')::numeric; v_manual := true; end if;
    if v_precio is null or v_precio < 0 then raise exception 'Falta el precio de %.', v_parte; end if;
    insert into venta_items (venta, parte, descripcion, cantidad, precio, precio_manual, faltante)
      values (v_id, v_parte, coalesce(v_desc, nullif(trim(it->>'descripcion'),'')), v_cant, v_precio, v_manual, greatest(v_cant - v_exist, 0))
      returning id into v_item;
    insert into venta_costos (item, costo) values (v_item, v_costo);
    update piezas set cantidad = greatest(cantidad - v_cant, 0), actualizado = now() where parte = v_parte;
    insert into movimientos (parte, cambio, cantidad_final, anaquel, motivo, usuario)
      values (v_parte, -least(v_cant, v_exist), greatest(v_exist - v_cant, 0), v_anaq, 'venta ' || v_id, auth.uid());
    v_total := v_total + v_precio * v_cant;
  end loop;
  update ventas set total = v_total,
    pagado = least(v_total, greatest(coalesce(p_pagado, case when p_tipo = 'contado' then v_total else 0 end), 0)) where id = v_id;
  return v_id;
end $$;

create or replace function cancelar_venta(p_id bigint, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r record; v_fin int;
begin
  if not ve_precios() then raise exception 'Solo quien pone precios puede cancelar una venta.'; end if;
  perform 1 from ventas where id = p_id and estado = 'cerrada' for update;
  if not found then raise exception 'La venta no existe o ya está cancelada.'; end if;
  for r in select parte, cantidad - faltante as regresa from venta_items where venta = p_id loop
    if r.regresa > 0 then
      update piezas set cantidad = cantidad + r.regresa, actualizado = now() where parte = r.parte returning cantidad into v_fin;
      insert into movimientos (parte, cambio, cantidad_final, anaquel, motivo, usuario)
        select r.parte, r.regresa, v_fin, anaquel, 'cancelación venta ' || p_id, auth.uid() from piezas where parte = r.parte;
    end if;
  end loop;
  update ventas set estado = 'cancelada', nota = concat_ws(' | ', nota, 'Cancelada: ' || coalesce(nullif(trim(p_motivo),''), 'sin motivo')) where id = p_id;
end $$;

create or replace function registrar_abono(p_cliente bigint, p_monto numeric, p_nota text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not es_personal() then raise exception 'Su usuario no tiene permiso.'; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'El abono debe ser mayor a cero.'; end if;
  perform 1 from clientes where id = p_cliente; if not found then raise exception 'El cliente no existe.'; end if;
  insert into abonos (cliente, monto, usuario, nota) values (p_cliente, p_monto, auth.uid(), nullif(trim(p_nota),'')) returning id into v_id;
  return v_id;
end $$;

create or replace function saldos_clientes() returns table (cliente bigint, nombre text, telefono text, saldo numeric, ultima timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.nombre, c.telefono,
    coalesce((select sum(v.total - v.pagado) from ventas v where v.cliente = c.id and v.tipo = 'credito' and v.estado = 'cerrada'), 0)
    - coalesce((select sum(a.monto) from abonos a where a.cliente = c.id), 0),
    (select max(v.fecha) from ventas v where v.cliente = c.id)
  from clientes c where es_personal() $$;

create or replace function registrar_entrada(p_items jsonb, p_proveedor text default null, p_factura text default null, p_nota text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb; v_parte text; v_cant int; v_costo numeric; v_anaq text; v_fin int; v_total numeric := 0;
begin
  if not es_personal() then raise exception 'Su usuario no tiene permiso.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'La entrada no tiene piezas.'; end if;
  insert into entradas (proveedor, factura, usuario, nota) values (nullif(trim(p_proveedor),''), nullif(trim(p_factura),''), auth.uid(), nullif(trim(p_nota),'')) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    v_parte := upper(regexp_replace(coalesce(it->>'parte',''), '\s', '', 'g'));
    v_cant := (it->>'cantidad')::int; v_costo := nullif(it->>'costo','')::numeric;
    if v_parte = '' then raise exception 'Hay una pieza sin número de parte.'; end if;
    if v_cant is null or v_cant < 1 then raise exception 'Cantidad no válida en %.', v_parte; end if;
    if v_costo is not null and v_costo < 0 then raise exception 'Costo no válido en %.', v_parte; end if;
    insert into piezas (parte, cantidad, anaquel, capturo, descripcion, proveedor)
      values (v_parte, v_cant, coalesce(nullif(trim(it->>'anaquel'),''), 'SIN-UBICAR'), auth.uid(), nullif(trim(it->>'descripcion'),''), nullif(trim(p_proveedor),''))
    on conflict (parte) do update set cantidad = piezas.cantidad + excluded.cantidad, actualizado = now(),
      proveedor = coalesce(excluded.proveedor, piezas.proveedor), descripcion = coalesce(piezas.descripcion, excluded.descripcion)
    returning cantidad, anaquel into v_fin, v_anaq;
    insert into entrada_items (entrada, parte, cantidad, costo) values (v_id, v_parte, v_cant, v_costo);
    insert into movimientos (parte, cambio, cantidad_final, anaquel, motivo, usuario) values (v_parte, v_cant, v_fin, v_anaq, 'entrada ' || v_id, auth.uid());
    if v_costo is not null then
      insert into precios (parte, costo) values (v_parte, v_costo)
      on conflict (parte) do update set costo = excluded.costo, actualizado = now();
    end if;
    update solicitadas set surtida = true where parte = v_parte and not surtida;
    v_total := v_total + coalesce(v_costo, 0) * v_cant;
  end loop;
  update entradas set total = v_total where id = v_id;
  return v_id;
end $$;

create or replace function reporte_ventas(p_desde date, p_hasta date) returns table (dia date, ventas bigint, total numeric, cobrado numeric, costo numeric, utilidad numeric)
language sql stable security definer set search_path = public as $$
  with v as (select id, (fecha at time zone 'America/Mazatlan')::date as dia, total, pagado from ventas
             where estado = 'cerrada' and es_personal() and (fecha at time zone 'America/Mazatlan')::date between p_desde and p_hasta),
       c as (select i.venta, sum(k.costo * i.cantidad) as costo, bool_and(k.costo is not null) as completo
             from venta_items i join venta_costos k on k.item = i.id group by i.venta)
  select v.dia, count(*), sum(v.total), sum(v.pagado),
    case when ve_precios() then sum(c.costo) end,
    case when ve_precios() then sum(v.total) filter (where c.completo) - sum(c.costo) filter (where c.completo) end
  from v left join c on c.venta = v.id group by v.dia order by v.dia $$;

create or replace function crear_pedido(p_items jsonb, p_nota text default null, p_cliente bigint default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_cli bigint; it jsonb; v_parte text; v_cant int;
begin
  if auth.uid() is null then raise exception 'Inicie sesión.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'El pedido no tiene piezas.'; end if;
  if es_personal() then v_cli := p_cliente;
  else select id into v_cli from clientes where usuario = auth.uid();
    if not found then raise exception 'Su usuario no está dado de alta como cliente. Avise a la refaccionaria.'; end if; end if;
  insert into pedidos (cliente, creado_por, nota) values (v_cli, auth.uid(), nullif(trim(p_nota),'')) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    v_parte := upper(regexp_replace(coalesce(it->>'parte',''), '\s', '', 'g')); v_cant := coalesce((it->>'cantidad')::int, 1);
    if v_parte = '' and coalesce(trim(it->>'descripcion'),'') = '' then raise exception 'Cada renglón necesita número de parte o descripción.'; end if;
    if v_cant < 1 then raise exception 'Cantidad no válida.'; end if;
    insert into pedido_items (pedido, parte, descripcion, cantidad) values (v_id, coalesce(nullif(v_parte,''), 'SIN-NUMERO'), nullif(trim(it->>'descripcion'),''), v_cant);
  end loop;
  return v_id;
end $$;

-- ===== Catálogo privado =====
insert into storage.buckets (id, name, public) values ('catalogos', 'catalogos', false) on conflict (id) do nothing;
drop policy if exists "leer catalogos con sesion" on storage.objects;
create policy "leer catalogos con sesion" on storage.objects for select to authenticated using (bucket_id = 'catalogos');

notify pgrst, 'reload schema';
