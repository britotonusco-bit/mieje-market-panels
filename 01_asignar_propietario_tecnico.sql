-- Ejecuta este SQL únicamente desde SQL Editor del proyecto MiEje Market.
-- Primero crea el usuario en Authentication > Users. Copia su UUID real y reemplaza el texto de abajo.
-- No uses el correo ni la contraseña como UUID. No compartas la contraseña.

UPDATE public.profiles
SET platform_role = 'platform_owner', updated_at = now()
WHERE id = 'REEMPLAZAR-POR-UUID-REAL-DEL-USUARIO'::uuid;

-- Verifica que se haya asignado el rol correcto:
SELECT id, display_name, platform_role
FROM public.profiles
WHERE id = 'REEMPLAZAR-POR-UUID-REAL-DEL-USUARIO'::uuid;

-- Debe aparecer platform_role = platform_owner. Si no actualizó ninguna fila,
-- confirma que el usuario ya existe en Authentication y que copiaste su UUID correcto.
