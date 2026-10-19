-- Saffron Table production ordering backend
create table if not exists public.restaurant_catalog (
  product_id integer primary key,
  category text not null,
  name_en text not null,
  name_ar text not null,
  price_egp integer not null check (price_egp > 0),
  available boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.restaurant_catalog(product_id,category,name_en,name_ar,price_egp) values
(1,'pasta','Creamy Tuscan Pasta','باستا توسكانية كريمية',245),
(2,'grill','Herb Butter Steak','ستيك بزبدة الأعشاب',385),
(3,'pizza','Burrata Garden Pizza','بيتزا بوراتا جاردن',225),
(4,'burgers','The Saffron Burger','برجر زعفران المميز',210),
(5,'starters','Roasted Garden Hummus','حمص الحديقة المشوي',115),
(6,'salads','Green Goddess Salad','سلطة جرين جودس',155),
(7,'pasta','Wild Mushroom Linguine','لينجويني بالمشروم البري',235),
(8,'grill','Smoky Mixed Grill','مشويات مشكلة مدخنة',320),
(9,'seafood','Lemon Garlic Sea Bass','قاروص بالليمون والثوم',345),
(10,'starters','Crispy Halloumi Bites','لقيمات حلوم مقرمشة',135),
(11,'pizza','Classic Margherita','مارجريتا الكلاسيكية',215),
(12,'burgers','Crispy Chicken Burger','برجر دجاج مقرمش',195),
(13,'seafood','Coastal Shrimp Linguine','لينجويني بالجمبري',285),
(14,'desserts','Pistachio Cheesecake','تشيز كيك بالفستق',125),
(15,'desserts','Chocolate Lava Cake','كيكة شوكولاتة لافا',110),
(16,'drinks','Citrus Garden Cooler','كوولر الحمضيات',75),
(17,'drinks','Iced Spanish Latte','لاتيه إسباني مثلج',85),
(18,'mains','Charred Veggie Bowl','بول الخضراوات المشوية',265)
on conflict(product_id) do update set category=excluded.category,name_en=excluded.name_en,name_ar=excluded.name_ar,price_egp=excluded.price_egp,updated_at=now();

create table if not exists public.restaurant_customers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  display_name text not null default '',
  phone text not null default '',
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists restaurant_customers_created_at_idx on public.restaurant_customers(created_at desc);

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create or replace function private.handle_new_restaurant_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.restaurant_customers(user_id,email,display_name,phone)
  values(new.id,lower(coalesce(new.email,'')),left(trim(coalesce(new.raw_user_meta_data->>'display_name','')),80),left(trim(coalesce(new.raw_user_meta_data->>'phone','')),25))
  on conflict(user_id) do nothing;
  return new;
end; $$;
revoke all on function private.handle_new_restaurant_auth_user() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_restaurant on auth.users;
create trigger on_auth_user_created_restaurant after insert on auth.users for each row execute function private.handle_new_restaurant_auth_user();
insert into public.restaurant_customers(user_id,email,display_name,phone)
select id,lower(coalesce(email,'')),left(trim(coalesce(raw_user_meta_data->>'display_name','')),80),left(trim(coalesce(raw_user_meta_data->>'phone','')),25) from auth.users
on conflict(user_id) do nothing;

create table if not exists public.restaurant_orders (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('ST-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  customer_id uuid references public.restaurant_customers(user_id) on delete set null,
  customer_name text not null,
  phone text not null,
  fulfillment_type text not null check (fulfillment_type in ('delivery','pickup')),
  delivery_address text not null default '',
  notes text not null default '',
  language text not null default 'en' check (language in ('en','ar')),
  payment_method text not null check (payment_method in ('cash_on_delivery','pay_at_pickup')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid','refunded')),
  subtotal_egp integer not null check (subtotal_egp >= 0),
  delivery_fee_egp integer not null default 0 check (delivery_fee_egp >= 0),
  total_egp integer not null check (total_egp = subtotal_egp + delivery_fee_egp),
  status text not null default 'pending' check (status in ('pending','confirmed','preparing','ready','out_for_delivery','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists restaurant_orders_created_at_idx on public.restaurant_orders(created_at desc);
create index if not exists restaurant_orders_phone_idx on public.restaurant_orders(phone);

create table if not exists public.restaurant_order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.restaurant_orders(id) on delete cascade,
  product_id integer not null,
  name_en text not null,
  name_ar text not null,
  quantity integer not null check (quantity between 1 and 20),
  unit_price_egp integer not null check (unit_price_egp > 0),
  line_total_egp integer not null check (line_total_egp = unit_price_egp * quantity),
  created_at timestamptz not null default now()
);
create index if not exists restaurant_order_items_order_id_idx on public.restaurant_order_items(order_id);

create table if not exists public.restaurant_reservations (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('RS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  customer_id uuid references public.restaurant_customers(user_id) on delete set null,
  customer_name text not null,
  phone text not null,
  reservation_date date not null,
  reservation_time text not null,
  guest_count integer not null check (guest_count between 1 and 20),
  occasion text not null default '',
  notes text not null default '',
  language text not null default 'en' check (language in ('en','ar')),
  status text not null default 'pending' check (status in ('pending','confirmed','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists restaurant_reservations_date_idx on public.restaurant_reservations(reservation_date,reservation_time);
create index if not exists restaurant_reservations_created_at_idx on public.restaurant_reservations(created_at desc);

create table if not exists public.restaurant_newsletter_subscribers (
  id bigint generated always as identity primary key,
  email text not null unique check (email = lower(trim(email)) and length(email) between 6 and 254),
  status text not null default 'pending_confirmation' check (status in ('pending_confirmation','subscribed','unsubscribed')),
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.restaurant_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.restaurant_rate_limits (
  rate_key text not null,
  action text not null,
  window_started_at timestamptz not null,
  hits integer not null default 1,
  primary key(rate_key,action,window_started_at)
);

alter table public.restaurant_catalog enable row level security;
alter table public.restaurant_customers enable row level security;
alter table public.restaurant_orders enable row level security;
alter table public.restaurant_order_items enable row level security;
alter table public.restaurant_reservations enable row level security;
alter table public.restaurant_newsletter_subscribers enable row level security;
alter table public.restaurant_staff enable row level security;
alter table public.restaurant_rate_limits enable row level security;

revoke all on public.restaurant_catalog from anon, authenticated;
revoke all on public.restaurant_customers from anon, authenticated;
revoke all on public.restaurant_orders from anon, authenticated;
revoke all on public.restaurant_order_items from anon, authenticated;
revoke all on public.restaurant_reservations from anon, authenticated;
revoke all on public.restaurant_newsletter_subscribers from anon, authenticated;
revoke all on public.restaurant_staff from anon, authenticated;
revoke all on public.restaurant_rate_limits from anon, authenticated;
grant select on public.restaurant_catalog to authenticated;
grant select, update on public.restaurant_customers to authenticated;
grant select, update on public.restaurant_orders to authenticated;
grant select on public.restaurant_order_items to authenticated;
grant select, update on public.restaurant_reservations to authenticated;
grant select on public.restaurant_newsletter_subscribers to authenticated;
grant select on public.restaurant_staff to authenticated;
grant all on public.restaurant_catalog, public.restaurant_customers, public.restaurant_orders, public.restaurant_order_items, public.restaurant_reservations, public.restaurant_newsletter_subscribers, public.restaurant_staff, public.restaurant_rate_limits to service_role;

drop policy if exists "Customer can read own profile" on public.restaurant_customers;
create policy "Customer can read own profile" on public.restaurant_customers for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Staff can view customers" on public.restaurant_customers;
create policy "Staff can view customers" on public.restaurant_customers for select to authenticated using(exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can update customer access" on public.restaurant_customers;
create policy "Staff can update customer access" on public.restaurant_customers for update to authenticated using(exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid()))) with check(exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Customer can read own orders" on public.restaurant_orders;
create policy "Customer can read own orders" on public.restaurant_orders for select to authenticated using(customer_id=(select auth.uid()) and exists(select 1 from public.restaurant_customers c where c.user_id=(select auth.uid()) and c.status='active'));
drop policy if exists "Customer can read own order items" on public.restaurant_order_items;
create policy "Customer can read own order items" on public.restaurant_order_items for select to authenticated using(exists(select 1 from public.restaurant_orders o join public.restaurant_customers c on c.user_id=o.customer_id where o.id=order_id and o.customer_id=(select auth.uid()) and c.status='active'));
drop policy if exists "Customer can read own reservations" on public.restaurant_reservations;
create policy "Customer can read own reservations" on public.restaurant_reservations for select to authenticated using(customer_id=(select auth.uid()) and exists(select 1 from public.restaurant_customers c where c.user_id=(select auth.uid()) and c.status='active'));

drop policy if exists "Staff can read own staff row" on public.restaurant_staff;
create policy "Staff can read own staff row" on public.restaurant_staff for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "Staff can read catalog" on public.restaurant_catalog;
create policy "Staff can read catalog" on public.restaurant_catalog for select to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can view orders" on public.restaurant_orders;
create policy "Staff can view orders" on public.restaurant_orders for select to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can update orders" on public.restaurant_orders;
create policy "Staff can update orders" on public.restaurant_orders for update to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid()))) with check (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can view order items" on public.restaurant_order_items;
create policy "Staff can view order items" on public.restaurant_order_items for select to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can view reservations" on public.restaurant_reservations;
create policy "Staff can view reservations" on public.restaurant_reservations for select to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can update reservations" on public.restaurant_reservations;
create policy "Staff can update reservations" on public.restaurant_reservations for update to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid()))) with check (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));
drop policy if exists "Staff can view newsletter subscribers" on public.restaurant_newsletter_subscribers;
create policy "Staff can view newsletter subscribers" on public.restaurant_newsletter_subscribers for select to authenticated using (exists(select 1 from public.restaurant_staff s where s.user_id=(select auth.uid())));

create or replace function public.consume_restaurant_rate_limit(p_rate_key text,p_action text,p_limit integer,p_window_seconds integer)
returns boolean language plpgsql set search_path=public,pg_temp as $$
declare v_window integer:=greatest(1,least(coalesce(p_window_seconds,600),86400)); v_bucket timestamptz; v_hits integer;
begin
 v_bucket:=to_timestamp(floor(extract(epoch from now())/v_window)*v_window);
 delete from public.restaurant_rate_limits where rate_key=p_rate_key and action=p_action and window_started_at<now()-interval '2 days';
 insert into public.restaurant_rate_limits(rate_key,action,window_started_at,hits) values(p_rate_key,p_action,v_bucket,1)
 on conflict(rate_key,action,window_started_at) do update set hits=public.restaurant_rate_limits.hits+1 returning hits into v_hits;
 return v_hits<=greatest(1,least(coalesce(p_limit,5),100));
end; $$;

create or replace function public.create_restaurant_order(p_customer_name text,p_phone text,p_fulfillment_type text,p_delivery_address text,p_notes text,p_language text,p_items jsonb,p_payment_method text,p_customer_id uuid)
returns jsonb language plpgsql set search_path=public,pg_temp as $$
declare v_order_id uuid; v_reference text; v_item record; v_product record; v_subtotal integer:=0; v_delivery integer:=0; v_language text:=case when p_language='ar' then 'ar' else 'en' end; v_payment_method text;
begin
 if p_customer_id is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
 if not exists(select 1 from public.restaurant_customers c where c.user_id=p_customer_id and c.status='active') then raise exception using errcode='28000',message='CUSTOMER_SUSPENDED'; end if;
 if exists(select 1 from public.restaurant_staff st where st.user_id=p_customer_id) then raise exception using errcode='28000',message='ADMIN_ACCOUNT_NOT_CUSTOMER'; end if;
 if length(trim(coalesce(p_customer_name,'')))<2 or length(trim(p_customer_name))>80 then raise exception using errcode='22023',message='INVALID_CUSTOMER_NAME'; end if;
 if coalesce(p_phone,'') !~ '^[+()0-9][+()0-9 .-]{5,24}$' then raise exception using errcode='22023',message='INVALID_PHONE'; end if;
 if p_fulfillment_type not in ('delivery','pickup') then raise exception using errcode='22023',message='INVALID_FULFILLMENT_TYPE'; end if;
 if p_fulfillment_type='delivery' and length(trim(coalesce(p_delivery_address,''))) not between 5 and 400 then raise exception using errcode='22023',message='INVALID_DELIVERY_ADDRESS'; end if;
 if length(coalesce(p_notes,''))>300 then raise exception using errcode='22023',message='NOTES_TOO_LONG'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>30 then raise exception using errcode='22023',message='INVALID_ORDER_ITEMS'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) e where coalesce(e->>'product_id',e->>'id','') !~ '^[0-9]{1,4}$' or coalesce(e->>'quantity','1') !~ '^[0-9]{1,2}$') then raise exception using errcode='22023',message='INVALID_ORDER_ITEMS'; end if;
 for v_item in select (coalesce(e->>'product_id',e->>'id'))::integer as product_id,sum(coalesce((e->>'quantity')::integer,1))::integer as quantity from jsonb_array_elements(p_items) e group by (coalesce(e->>'product_id',e->>'id'))::integer loop
  if v_item.quantity<1 or v_item.quantity>20 then raise exception using errcode='22023',message='INVALID_ITEM_QUANTITY'; end if;
  select c.product_id,c.name_en,c.name_ar,c.price_egp into v_product from public.restaurant_catalog c where c.product_id=v_item.product_id and c.available=true;
  if not found then raise exception using errcode='22023',message='PRODUCT_UNAVAILABLE'; end if;
  v_subtotal:=v_subtotal+v_product.price_egp*v_item.quantity;
 end loop;
 v_delivery:=case when p_fulfillment_type='delivery' then 35 else 0 end;
 v_payment_method:=case when p_fulfillment_type='delivery' then 'cash_on_delivery' else 'pay_at_pickup' end;
 if p_payment_method is not null and p_payment_method<>v_payment_method then raise exception using errcode='22023',message='INVALID_PAYMENT_METHOD'; end if;
 insert into public.restaurant_orders(customer_id,customer_name,phone,fulfillment_type,delivery_address,notes,language,payment_method,subtotal_egp,delivery_fee_egp,total_egp)
 values(p_customer_id,trim(p_customer_name),trim(p_phone),p_fulfillment_type,case when p_fulfillment_type='pickup' then '' else trim(p_delivery_address) end,trim(coalesce(p_notes,'')),v_language,v_payment_method,v_subtotal,v_delivery,v_subtotal+v_delivery)
 returning id,reference into v_order_id,v_reference;
 insert into public.restaurant_order_items(order_id,product_id,name_en,name_ar,quantity,unit_price_egp,line_total_egp)
 select v_order_id,c.product_id,c.name_en,c.name_ar,q.quantity,c.price_egp,c.price_egp*q.quantity from
 (select (coalesce(e->>'product_id',e->>'id'))::integer as product_id,sum(coalesce((e->>'quantity')::integer,1))::integer as quantity from jsonb_array_elements(p_items) e group by (coalesce(e->>'product_id',e->>'id'))::integer) q
 join public.restaurant_catalog c on c.product_id=q.product_id and c.available=true;
 return jsonb_build_object('id',v_order_id,'reference',v_reference,'status','pending','payment_method',v_payment_method,'payment_status','unpaid','fulfillment_type',p_fulfillment_type,'subtotal_egp',v_subtotal,'delivery_fee_egp',v_delivery,'total_egp',v_subtotal+v_delivery,'currency','EGP');
end; $$;

create or replace function public.create_restaurant_reservation(p_customer_name text,p_phone text,p_reservation_date date,p_reservation_time text,p_guest_count integer,p_occasion text,p_notes text,p_language text,p_customer_id uuid)
returns jsonb language plpgsql set search_path=public,pg_temp as $$
declare v_id uuid; v_reference text;
begin
 if p_customer_id is null then raise exception using errcode='28000',message='AUTH_REQUIRED'; end if;
 if not exists(select 1 from public.restaurant_customers c where c.user_id=p_customer_id and c.status='active') then raise exception using errcode='28000',message='CUSTOMER_SUSPENDED'; end if;
 if exists(select 1 from public.restaurant_staff st where st.user_id=p_customer_id) then raise exception using errcode='28000',message='ADMIN_ACCOUNT_NOT_CUSTOMER'; end if;
 if length(trim(coalesce(p_customer_name,'')))<2 or length(trim(p_customer_name))>80 then raise exception using errcode='22023',message='INVALID_CUSTOMER_NAME'; end if;
 if coalesce(p_phone,'') !~ '^[+()0-9][+()0-9 .-]{5,24}$' then raise exception using errcode='22023',message='INVALID_PHONE'; end if;
 if p_reservation_date is null or p_reservation_date<(now() at time zone 'Africa/Cairo')::date then raise exception using errcode='22023',message='INVALID_RESERVATION_DATE'; end if;
 if length(trim(coalesce(p_reservation_time,'')))<3 or length(trim(p_reservation_time))>40 then raise exception using errcode='22023',message='INVALID_RESERVATION_TIME'; end if;
 if p_guest_count is null or p_guest_count<1 or p_guest_count>20 then raise exception using errcode='22023',message='INVALID_GUEST_COUNT'; end if;
 if length(coalesce(p_occasion,''))>80 or length(coalesce(p_notes,''))>400 then raise exception using errcode='22023',message='RESERVATION_DETAILS_TOO_LONG'; end if;
 insert into public.restaurant_reservations(customer_id,customer_name,phone,reservation_date,reservation_time,guest_count,occasion,notes,language)
 values(p_customer_id,trim(p_customer_name),trim(p_phone),p_reservation_date,trim(p_reservation_time),p_guest_count,trim(coalesce(p_occasion,'')),trim(coalesce(p_notes,'')),case when p_language='ar' then 'ar' else 'en' end)
 returning id,reference into v_id,v_reference;
 return jsonb_build_object('id',v_id,'reference',v_reference,'status','pending','reservation_date',p_reservation_date,'reservation_time',trim(p_reservation_time),'guest_count',p_guest_count);
end; $$;

create or replace function public.lookup_restaurant_order(p_reference text,p_phone text) returns jsonb
language plpgsql set search_path=public,pg_temp as $$
declare v_order record;
begin
 select o.id,o.reference,o.status,o.fulfillment_type,o.payment_status,o.subtotal_egp,o.delivery_fee_egp,o.total_egp,o.created_at,o.updated_at into v_order
 from public.restaurant_orders o where upper(o.reference)=upper(trim(coalesce(p_reference,''))) and regexp_replace(o.phone,'[^0-9]','','g')=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
 if not found then return null; end if;
 return jsonb_build_object('reference',v_order.reference,'status',v_order.status,'fulfillment_type',v_order.fulfillment_type,'payment_status',v_order.payment_status,'subtotal_egp',v_order.subtotal_egp,'delivery_fee_egp',v_order.delivery_fee_egp,'total_egp',v_order.total_egp,'created_at',v_order.created_at,'updated_at',v_order.updated_at,
 'items',(select coalesce(jsonb_agg(jsonb_build_object('product_id',i.product_id,'name_en',i.name_en,'name_ar',i.name_ar,'quantity',i.quantity,'unit_price_egp',i.unit_price_egp,'line_total_egp',i.line_total_egp) order by i.id),'[]'::jsonb) from public.restaurant_order_items i where i.order_id=v_order.id));
end; $$;

revoke all on function public.consume_restaurant_rate_limit(text,text,integer,integer) from public,anon,authenticated;
revoke all on function public.create_restaurant_order(text,text,text,text,text,text,jsonb,text,uuid) from public,anon,authenticated;
revoke all on function public.create_restaurant_reservation(text,text,date,text,integer,text,text,text,uuid) from public,anon,authenticated;
revoke all on function public.lookup_restaurant_order(text,text) from public,anon,authenticated;
grant execute on function public.consume_restaurant_rate_limit(text,text,integer,integer) to service_role;
grant execute on function public.create_restaurant_order(text,text,text,text,text,text,jsonb,text,uuid) to service_role;
grant execute on function public.create_restaurant_reservation(text,text,date,text,integer,text,text,text,uuid) to service_role;
grant execute on function public.lookup_restaurant_order(text,text) to service_role;
