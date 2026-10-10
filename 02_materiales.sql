-- =============================================================================
-- Módulo 02: Tabla de Materiales y Generador de Código
-- Descripción: Registro de materiales con cálculo automático de código:
--              - 1 palabra: 4 primeras letras (ej. Cartón -> CART)
--              - 2 o más palabras: 2 letras de la 1ª palabra + 2 letras de la 2ª (ej. Cartón Corrugado -> CACO)
--              - Fecha: DDMMYY
--              - Dígito: Suma de los dígitos reducida a 1 solo número
--              - Regla 1: El nombre del material debe ser ÚNICO
--              - Regla 2: nombre, fecha_creacion y codigo son INMUTABLES
--              - Regla 3: activo es booleano y SÍ es mutable (activar/desactivar)
-- =============================================================================

-- 1. Función para calcular el código según la regla de negocio
CREATE OR REPLACE FUNCTION fn_generar_codigo_material(p_nombre TEXT, p_fecha DATE)
RETURNS VARCHAR(50) AS $$
DECLARE
    v_nombre_limpio TEXT;
    v_palabras TEXT[];
    v_num_palabras INT;
    v_prefijo TEXT;
    v_fecha_str TEXT;
    v_suma INT := 0;
    v_i INT;
BEGIN
    -- Limpieza: mayúsculas, remoción de acentos y normalización de espacios múltiples
    v_nombre_limpio := UPPER(TRANSLATE(TRIM(p_nombre), 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'));
    v_nombre_limpio := REGEXP_REPLACE(v_nombre_limpio, '\s+', ' ', 'g');

    -- Separar el nombre en palabras
    v_palabras := STRING_TO_ARRAY(v_nombre_limpio, ' ');
    v_num_palabras := ARRAY_LENGTH(v_palabras, 1);

    -- Lógica para el prefijo de 4 letras
    IF v_num_palabras >= 2 THEN
        -- 2 o más palabras: 2 primeras letras de la 1ª y 2 primeras letras de la 2ª
        -- Ej: "Cartón Corrugado" -> "CA" + "CO" = "CACO"
        v_prefijo := RPAD(SUBSTRING(v_palabras[1] FROM 1 FOR 2), 2, 'X') ||
                     RPAD(SUBSTRING(v_palabras[2] FROM 1 FOR 2), 2, 'X');
    ELSE
        -- 1 palabra: 4 primeras letras (si tiene menos de 4, rellena con 'X')
        -- Ej: "Cartón" -> "CART", "PET" -> "PETX"
        v_prefijo := RPAD(SUBSTRING(v_palabras[1] FROM 1 FOR 4), 4, 'X');
    END IF;

    -- Fecha en formato DDMMYY (ej: 08-10-2026 -> "081026")
    v_fecha_str := TO_CHAR(p_fecha, 'DDMMYY');

    -- Suma de los dígitos de la fecha
    FOR v_i IN 1..LENGTH(v_fecha_str) LOOP
        v_suma := v_suma + SUBSTRING(v_fecha_str FROM v_i FOR 1)::INT;
    END LOOP;

    -- Reducción a 1 solo dígito si la suma es >= 10
    WHILE v_suma >= 10 LOOP
        v_suma := (v_suma / 10) + (v_suma % 10);
    END LOOP;

    -- Código final: PREFIJO-DDMMYY-DIGITO (ej: CART-081026-8 o CACO-081026-8)
    RETURN v_prefijo || '-' || v_fecha_str || '-' || v_suma::TEXT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 2. Tabla Materiales
CREATE TABLE IF NOT EXISTS materiales (
    codigo VARCHAR(50) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    fecha_creacion DATE NOT NULL DEFAULT CURRENT_DATE,
    activo BOOLEAN NOT NULL DEFAULT FALSE
);

-- Asegurar la columna 'activo' y su valor por defecto FALSE si la tabla ya existía
ALTER TABLE materiales ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE materiales ALTER COLUMN activo SET DEFAULT FALSE;

-- Asegurar la restricción UNIQUE si la tabla se creó previamente sin ella
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'materiales'::regclass AND contype = 'u'
    ) THEN
        ALTER TABLE materiales ADD CONSTRAINT uq_materiales_nombre UNIQUE (nombre);
    END IF;
END $$;

-- 3. Trigger para autogenerar el código antes de insertar si no viene especificado
CREATE OR REPLACE FUNCTION trg_asignar_codigo_material()
RETURNS TRIGGER AS $$
BEGIN
    -- Asegurar que la fecha esté asignada antes de generar el código
    IF NEW.fecha_creacion IS NULL THEN
        NEW.fecha_creacion := CURRENT_DATE;
    END IF;

    -- Generar el código solo si no se pasó uno manualmente
    IF NEW.codigo IS NULL OR NEW.codigo = '' THEN
        NEW.codigo := fn_generar_codigo_material(NEW.nombre, NEW.fecha_creacion);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_materiales_bi ON materiales;
CREATE TRIGGER trg_materiales_bi
BEFORE INSERT ON materiales
FOR EACH ROW
EXECUTE FUNCTION trg_asignar_codigo_material();

-- 4. Trigger para garantizar la inmutabilidad de nombre, fecha_creacion y código
CREATE OR REPLACE FUNCTION trg_materiales_inmutable()
RETURNS TRIGGER AS $$
BEGIN
    -- Bloquear cambios al nombre
    IF NEW.nombre IS DISTINCT FROM OLD.nombre THEN
        RAISE EXCEPTION 'Operación rechazada: el nombre del material es inmutable ya que el código depende de él.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Bloquear cambios a la fecha de creación
    IF NEW.fecha_creacion IS DISTINCT FROM OLD.fecha_creacion THEN
        RAISE EXCEPTION 'Operación rechazada: la fecha de creación del material es inmutable ya que el código depende de ella.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Bloquear cambios a la PK (código)
    IF NEW.codigo IS DISTINCT FROM OLD.codigo THEN
        RAISE EXCEPTION 'Operación rechazada: el código del material es la clave primaria y no puede ser modificado.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Nota: La columna 'activo' SÍ es mutable (se permite activar o desactivar)
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_materiales_bu ON materiales;
CREATE TRIGGER trg_materiales_bu
BEFORE UPDATE ON materiales
FOR EACH ROW
EXECUTE FUNCTION trg_materiales_inmutable();

-- Comentarios explicativos
COMMENT ON TABLE materiales IS 'Catálogo de tipos de materiales recibidos en el centro';
COMMENT ON COLUMN materiales.codigo IS 'Código autogenerado e inmutable con formato [4_LETRAS]-[DDMMYY]-[DIGITO_SUMA]';
COMMENT ON COLUMN materiales.nombre IS 'Nombre único e inmutable del material';
COMMENT ON COLUMN materiales.fecha_creacion IS 'Fecha de registro inmutable del material';
COMMENT ON COLUMN materiales.activo IS 'Estado del material: true (activo/disponible), false (desactivado)';
