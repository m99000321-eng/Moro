# Saffron Table backend setup

The public site is deployed on Vercel and the database/API live in the linked Supabase project.

## Public routes
- Restaurant: https://noir-cinematic-studio.vercel.app/
- Customer sign-in / registration / account: https://noir-cinematic-studio.vercel.app/customer.html
- Staff/admin console: https://noir-cinematic-studio.vercel.app/admin.html

## One-time first admin setup
Admin access is **not** selectable during registration. A user's role is checked against `public.restaurant_staff` on the server/database.

1. Open `customer.html` and register using the email you want to use for the administrator.
2. Confirm the email if Supabase asks you to.
3. Open the Supabase Dashboard for project `erosjbwpjcgtoocltvqq`, then open SQL Editor.
4. Copy `supabase/first-admin.sql`, replace `REPLACE_WITH_YOUR_ADMIN_EMAIL` with the same verified email, and run it.
5. Open `admin.html` and sign in with that account. A normal customer is redirected to the customer page.

Only a project owner with SQL Editor access can bootstrap the first staff account. Do not expose the service-role key or add a client-side “make me admin” action.

## Current capabilities
- Customer account registration and sign-in with Supabase Auth.
- Restaurant orders and reservations written to PostgreSQL.
- Prices and totals recalculated on the server from the catalog.
- Customer account area only reads that customer's orders/reservations, protected by RLS.
- Staff console can view orders/reservations, update their statuses, suspend/restore customers, and permanently delete a customer account.
- Newsletter emails are recorded as pending confirmation. A transactional email/confirmation provider is not connected.
- Payment methods are cash on delivery / pay-at-pickup. Online payment is not connected.

## Before accepting public customers
1. Add the first admin using the steps above.
2. Add the real restaurant address, phone, opening hours, delivery areas/fees, actual menu and prices.
3. Test signup/email confirmation, one test order, one reservation, admin status changes, suspended-user rejection and customer deletion.
4. Configure custom Auth email templates/SMTP before relying on email confirmations at scale.

The Edge Function's service-role credential is server-side only. The public frontend contains only the publishable key.
