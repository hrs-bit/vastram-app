-- Run ONLY after you have created the accounts through the Vastram sign-up screen.
-- Replace the emails with your own test accounts.
-- Never give users admin role through the frontend.

update public.profiles p
set role='admin'
from auth.users u
where p.id=u.id and u.email='YOUR_ADMIN_EMAIL@example.com';

update public.profiles p
set role='merchant'
from auth.users u
where p.id=u.id and u.email='YOUR_MERCHANT_EMAIL@example.com';

update public.profiles p
set role='agent'
from auth.users u
where p.id=u.id and u.email='YOUR_AGENT_EMAIL@example.com';

-- Verify
select p.id,u.email,p.full_name,p.role,p.shop_id,p.active
from public.profiles p join auth.users u on u.id=p.id
order by u.email;
