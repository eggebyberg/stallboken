-- Gör dig själv till admin i Stallboken.
-- Byt ut e-postadressen nedan mot den du skapade ditt konto med,
-- klistra in i SQL Editor och klicka Run.
update public.profiles
set is_admin = true,
    name = coalesce(nullif(name, ''), 'Admin')
where email = 'DIN-EPOST@exempel.se';

select name, email, is_admin from public.profiles;
