-- VASTRAM v0.7 secure zero-cost-first schema
create extension if not exists pgcrypto;

create table if not exists public.shops (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 owner_id uuid references auth.users(id) on delete cascade,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '',
 role text not null default 'customer' check(role in ('customer','merchant','agent','admin')),
 shop_id uuid references public.shops(id) on delete set null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(), shop_id uuid references public.shops(id) on delete cascade,
 name text not null, category text not null, price integer not null check(price>=0), image_url text,
 active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(), order_code text unique not null,
 shop_id uuid references public.shops(id), shop_name text not null,
 customer_id uuid references auth.users(id), customer_name text not null,
 item_name text not null, amount integer not null default 0 check(amount>=0),
 distance_km numeric(6,2) not null default 0, eta_minutes integer,
 traffic text check(traffic in ('low','medium','high')) default 'medium',
 status text not null default 'ready_for_pickup' check(status in ('placed','merchant_accepted','preparing','ready_for_pickup','picked_up','out_for_delivery','arrived','tryon','completed','return_requested')),
 customer_token text unique not null,
 agent_id uuid references auth.users(id),
 agent_token text,
 otp_code text not null,
 otp_hash text not null,
 otp_expires_at timestamptz not null default (now()+interval '30 minutes'),
 handover_at timestamptz, tryon_ends_at timestamptz,
 decision text check(decision in ('keep','return')),
 created_at timestamptz not null default now()
);

-- Automatically create a customer profile on signup.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name,role) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),'customer') on conflict(id) do nothing; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
revoke all on public.profiles,public.shops,public.products,public.orders from anon;
grant select,insert,update on public.profiles,public.shops,public.products to authenticated;
revoke all on public.orders from authenticated;

drop policy if exists profile_self on public.profiles;
create policy profile_self on public.profiles for select using(auth.uid()=id);
drop policy if exists profile_self_update on public.profiles;
create policy profile_self_update on public.profiles for update using(auth.uid()=id) with check(auth.uid()=id);

drop policy if exists shop_owner on public.shops;
create policy shop_owner on public.shops for all to authenticated using(owner_id=auth.uid() or exists(select 1 from profiles p where p.id=auth.uid() and p.role='admin')) with check(owner_id=auth.uid() or exists(select 1 from profiles p where p.id=auth.uid() and p.role='admin'));

drop policy if exists products_public on public.products;
create policy products_public on public.products for select to authenticated using(active=true);
drop policy if exists shop_owner_products on public.products;
create policy shop_owner_products on public.products for all to authenticated using(shop_id in(select shop_id from profiles where id=auth.uid() and role='merchant')) with check(shop_id in(select shop_id from profiles where id=auth.uid() and role='merchant'));

drop policy if exists order_customer_read on public.orders;
create policy order_customer_read on public.orders for select to authenticated using(customer_id=auth.uid());
drop policy if exists order_merchant_read on public.orders;
create policy order_merchant_read on public.orders for select to authenticated using(shop_id in(select shop_id from profiles where id=auth.uid() and role='merchant'));
drop policy if exists order_agent_read on public.orders;
create policy order_agent_read on public.orders for select to authenticated using(agent_id=auth.uid());
drop policy if exists order_admin_read on public.orders;
create policy order_admin_read on public.orders for select to authenticated using(exists(select 1 from profiles where id=auth.uid() and role='admin' and active));

create or replace function public.my_profile() returns public.profiles language sql security definer set search_path=public as $$ select * from profiles where id=auth.uid() and active limit 1; $$;
create or replace function public.create_shop(p_name text) returns public.shops language plpgsql security definer set search_path=public as $$
declare s public.shops; begin if auth.uid() is null then raise exception 'Login required'; end if; if not exists(select 1 from profiles where id=auth.uid() and role='merchant' and active) then raise exception 'Merchant access required'; end if; insert into shops(name,owner_id) values(trim(p_name),auth.uid()) returning * into s; update profiles set shop_id=s.id where id=auth.uid(); return s; end $$;

create or replace function public.create_order(p_shop_id uuid,p_customer_name text,p_item_name text,p_amount integer,p_distance_km numeric) returns json language plpgsql security definer set search_path=public as $$
declare o public.orders; s public.shops; code text; raw text; h text; shopid uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if not exists(select 1 from profiles where id=auth.uid() and role='merchant' and active) then raise exception 'Merchant access required'; end if;
 select shop_id into shopid from profiles where id=auth.uid();
 if shopid is null then raise exception 'Create a shop before creating orders'; end if;
 select * into s from shops where id=shopid and owner_id=auth.uid() and active;
 if not found then raise exception 'Merchant shop not found'; end if;
 code:='VST-'||upper(substr(encode(gen_random_bytes(4),'hex'),1,6)); raw:=lpad((floor(random()*10000))::int::text,4,'0'); h:=encode(digest(raw,'sha256'),'hex');
 insert into orders(order_code,shop_id,shop_name,customer_name,item_name,amount,distance_km,status,customer_token,otp_code,otp_hash)
 values(code,s.id,s.name,trim(p_customer_name),trim(p_item_name),p_amount,p_distance_km,'ready_for_pickup',encode(gen_random_bytes(16),'hex'),raw,h) returning * into o;
 return json_build_object('id',o.id,'order_code',o.order_code,'shop_id',o.shop_id,'shop_name',o.shop_name,'customer_name',o.customer_name,'item_name',o.item_name,'amount',o.amount,'distance_km',o.distance_km,'status',o.status,'customer_token',o.customer_token);
end $$;

create or replace function public.customer_order(p_customer_token text) returns json language sql security definer set search_path=public as $$
 select to_jsonb(x) - 'otp_hash' from orders x where customer_token=p_customer_token limit 1; $$;

create or replace function public.claim_delivery_order(p_shop_code text,p_agent_token text) returns public.orders language plpgsql security definer set search_path=public as $$
declare o public.orders; uid uuid;
begin
 uid:=auth.uid(); if uid is null then raise exception 'Login required'; end if;
 if not exists(select 1 from profiles where id=uid and role='agent' and active) then raise exception 'Delivery agent access required'; end if;
 if length(coalesce(p_agent_token,''))<12 then raise exception 'Invalid agent session'; end if;
 select * into o from orders where order_code=p_shop_code and status='ready_for_pickup' for update;
 if not found then raise exception 'Order not available'; end if;
 update orders set status='picked_up',agent_id=uid,agent_token=p_agent_token where id=o.id returning * into o; return o;
end $$;
create or replace function public.set_delivery_eta(p_agent_token text,p_eta_minutes integer,p_distance_km numeric,p_traffic text) returns public.orders language plpgsql security definer set search_path=public as $$
declare o public.orders; begin if not exists(select 1 from profiles where id=auth.uid() and role='agent' and active) then raise exception 'Delivery agent access required'; end if; if p_eta_minutes<1 or p_eta_minutes>180 then raise exception 'Invalid ETA'; end if; update orders set eta_minutes=p_eta_minutes,distance_km=p_distance_km,traffic=p_traffic,status='out_for_delivery' where agent_id=auth.uid() and agent_token=p_agent_token and status in('picked_up','out_for_delivery') returning * into o; if not found then raise exception 'Delivery session not found'; end if; return o; end $$;
create or replace function public.mark_delivery_arrived(p_agent_token text) returns public.orders language plpgsql security definer set search_path=public as $$
declare o public.orders; begin if not exists(select 1 from profiles where id=auth.uid() and role='agent' and active) then raise exception 'Delivery agent access required'; end if; update orders set status='arrived' where agent_id=auth.uid() and agent_token=p_agent_token and status='out_for_delivery' returning * into o; if not found then raise exception 'Delivery is not in transit'; end if; return o; end $$;
create or replace function public.verify_handover(p_agent_token text,p_otp text) returns public.orders language plpgsql security definer set search_path=public as $$
declare o public.orders; begin if not exists(select 1 from profiles where id=auth.uid() and role='agent' and active) then raise exception 'Delivery agent access required'; end if; select * into o from orders where agent_id=auth.uid() and agent_token=p_agent_token and status='arrived' for update; if not found then raise exception 'Order is not awaiting handover'; end if; if o.otp_expires_at<now() or encode(digest(p_otp,'sha256'),'hex')<>o.otp_hash then raise exception 'Invalid or expired OTP'; end if; update orders set status='tryon',handover_at=now(),tryon_ends_at=now()+interval '5 minutes' where id=o.id returning * into o; return o; end $$;
create or replace function public.finish_tryon(p_agent_token text,p_decision text) returns public.orders language plpgsql security definer set search_path=public as $$
declare o public.orders; begin if not exists(select 1 from profiles where id=auth.uid() and role='agent' and active) then raise exception 'Delivery agent access required'; end if; if p_decision not in('keep','return') then raise exception 'Invalid decision'; end if; update orders set status=case when p_decision='keep' then 'completed' else 'return_requested' end,decision=p_decision where agent_id=auth.uid() and agent_token=p_agent_token and status='tryon' returning * into o; if not found then raise exception 'Try-on session not active'; end if; return o; end $$;
create or replace function public.merchant_orders(p_shop_id uuid) returns setof public.orders language sql security definer set search_path=public as $$ select * from orders where shop_id=p_shop_id and shop_id=(select shop_id from profiles where id=auth.uid() and role='merchant') order by created_at desc; $$;
create or replace function public.admin_stats() returns json language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from profiles where id=auth.uid() and role='admin' and active) then raise exception 'Admin access required'; end if; return json_build_object('orders',(select count(*) from orders),'agents',(select count(*) from profiles where role='agent' and active),'merchants',(select count(*) from profiles where role='merchant' and active),'returns',(select count(*) from orders where status='return_requested')); end $$;
create or replace function public.admin_orders() returns setof public.orders language plpgsql security definer set search_path=public as $$ begin if not exists(select 1 from profiles where id=auth.uid() and role='admin' and active) then raise exception 'Admin access required'; end if; return query select * from orders order by created_at desc limit 100; end $$;
create or replace function public.admin_update_order(p_order_id uuid,p_status text) returns public.orders language plpgsql security definer set search_path=public as $$ declare o public.orders; begin if not exists(select 1 from profiles where id=auth.uid() and role='admin' and active) then raise exception 'Admin access required'; end if; if p_status not in ('placed','merchant_accepted','preparing','ready_for_pickup','picked_up','out_for_delivery','arrived','tryon','completed','return_requested') then raise exception 'Invalid status'; end if; update orders set status=p_status where id=p_order_id returning * into o; if not found then raise exception 'Order not found'; end if; return o; end $$;

revoke all on function public.my_profile() from public,anon;
revoke all on function public.create_shop(text) from public,anon;
revoke all on function public.create_order(uuid,text,text,integer,numeric) from public,anon;
revoke all on function public.customer_order(text) from public,anon;
revoke all on function public.claim_delivery_order(text,text) from public,anon;
revoke all on function public.set_delivery_eta(text,integer,numeric,text) from public,anon;
revoke all on function public.mark_delivery_arrived(text) from public,anon;
revoke all on function public.verify_handover(text,text) from public,anon;
revoke all on function public.finish_tryon(text,text) from public,anon;
revoke all on function public.merchant_orders(uuid) from public,anon;
revoke all on function public.admin_stats() from public,anon;
revoke all on function public.admin_orders() from public,anon;
revoke all on function public.admin_update_order(uuid,text) from public,anon;
grant execute on function public.my_profile(),public.create_shop(text),public.create_order(uuid,text,text,integer,numeric),public.customer_order(text),public.claim_delivery_order(text,text),public.set_delivery_eta(text,integer,numeric,text),public.mark_delivery_arrived(text),public.verify_handover(text,text),public.finish_tryon(text,text),public.merchant_orders(uuid),public.admin_stats(),public.admin_orders(),public.admin_update_order(uuid,text) to authenticated;

-- Production note: otp_code is only returned by the bearer customer_order() RPC; do not expose it through direct table access.
