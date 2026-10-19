-- First-time setup: promote your own verified account to restaurant staff/admin.
-- 1) Sign up at https://noir-cinematic-studio.vercel.app/customer.html using your admin email.
-- 2) Confirm the email (if confirmation is enabled).
-- 3) Replace the placeholder below with that exact email and run this in Supabase SQL Editor.
-- This SQL should be run only by the project owner. Never add public self-registration to restaurant_staff.

insert into public.restaurant_staff (user_id, display_name)
select u.id, 'Restaurant Admin'
from auth.users u
where lower(u.email) = lower('REPLACE_WITH_YOUR_ADMIN_EMAIL')
on conflict (user_id) do nothing;
