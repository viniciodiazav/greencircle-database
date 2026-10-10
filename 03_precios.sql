-- =============================================================================
-- Módulo 03: Precios e Históricos (Compra y Venta)
-- Descripción:
--   1. Tabla 'precios': Almacena el precio actual de compra y venta por material.
--      Su PK y FK es 'codigo' referenciando a 'materiales'.
--   2. Tablas 'historico_precios_compra' e 'historico_precios_venta':
--      - PK: [Consecutivo autogenerado]-[Año actual] (ej. 1-2026, 2-2026).
--      - Vigencia: 'vigente_hasta' es NULL para el precio activo.
--      - Regla de oro: No puede haber 2 registros con el mismo código de material
--        y vigente_hasta en NULL simultáneamente (controlado por índice único parcial).
--   3. Trigger automático: Al insertar o actualizar precios, gestiona los históricos.
-- =============================================================================

-- 1. Tabla de Precios Actuales
CREATE TABLE IF NOT EXISTS precios (
    codigo VARCHAR(50) PRIMARY KEY REFERENCES materiales(codigo) ON DELETE CASCADE,
    precio_venta NUMERIC(12, 2) NOT NULL CHECK (precio_venta >= 0),
    precio_compra NUMERIC(12, 2) NOT NULL CHECK (precio_compra >= 0),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Tabla Histórico de Precios de Compra
CREATE TABLE IF NOT EXISTS historico_precios_compra (
    id VARCHAR(50) PRIMARY KEY,
    codigo_material VARCHAR(50) NOT NULL REFERENCES materiales(codigo) ON DELETE CASCADE,
    precio NUMERIC(12, 2) NOT NULL CHECK (precio >= 0),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    vigente_hasta TIMESTAMPTZ NULL
);

-- Restricción estricta: Máximo 1 tupla activa (vigente_hasta IS NULL) por material
CREATE UNIQUE INDEX IF NOT EXISTS uq_hist_compra_vigente_activo 
ON historico_precios_compra (codigo_material) 
WHERE vigente_hasta IS NULL;

-- 3. Tabla Histórico de Precios de Venta
CREATE TABLE IF NOT EXISTS historico_precios_venta (
    id VARCHAR(50) PRIMARY KEY,
    codigo_material VARCHAR(50) NOT NULL REFERENCES materiales(codigo) ON DELETE CASCADE,
    precio NUMERIC(12, 2) NOT NULL CHECK (precio >= 0),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    vigente_hasta TIMESTAMPTZ NULL
);

-- Restricción estricta: Máximo 1 tupla activa (vigente_hasta IS NULL) por material
CREATE UNIQUE INDEX IF NOT EXISTS uq_hist_venta_vigente_activo 
ON historico_precios_venta (codigo_material) 
WHERE vigente_hasta IS NULL;

-- 4. Función para generar el ID anual del histórico: [Consecutivo]-[Año] (ej. 1-2026)
CREATE OR REPLACE FUNCTION fn_generar_id_historico(p_tipo TEXT)
RETURNS VARCHAR(50) AS $$
DECLARE
    v_anio TEXT;
    v_consecutivo INT;
BEGIN
    v_anio := TO_CHAR(CURRENT_DATE, 'YYYY');

    IF p_tipo = 'compra' THEN
        SELECT COALESCE(MAX(SPLIT_PART(id, '-', 1)::INT), 0) + 1
        INTO v_consecutivo
        FROM historico_precios_compra
        WHERE id LIKE '%-' || v_anio;
    ELSE
        SELECT COALESCE(MAX(SPLIT_PART(id, '-', 1)::INT), 0) + 1
        INTO v_consecutivo
        FROM historico_precios_venta
        WHERE id LIKE '%-' || v_anio;
    END IF;

    RETURN v_consecutivo::TEXT || '-' || v_anio;
END;
$$ LANGUAGE plpgsql;

-- 5. Trigger BEFORE UPDATE en 'precios' para refrescar 'actualizado_en'
CREATE OR REPLACE FUNCTION trg_precios_bu_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.actualizado_en := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_precios_bu ON precios;
CREATE TRIGGER trg_precios_bu
BEFORE UPDATE ON precios
FOR EACH ROW
EXECUTE FUNCTION trg_precios_bu_timestamp();

-- 6. Trigger AFTER INSERT OR UPDATE en 'precios' para alimentar los históricos
CREATE OR REPLACE FUNCTION trg_gestionar_historico_precios()
RETURNS TRIGGER AS $$
BEGIN
    -- CASO 1: Inserción inicial de precios
    IF TG_OP = 'INSERT' THEN
        -- Registrar histórico inicial de compra
        INSERT INTO historico_precios_compra (id, codigo_material, precio, creado_en, vigente_hasta)
        VALUES (
            fn_generar_id_historico('compra'),
            NEW.codigo,
            NEW.precio_compra,
            NEW.actualizado_en,
            NULL
        );

        -- Registrar histórico inicial de venta
        INSERT INTO historico_precios_venta (id, codigo_material, precio, creado_en, vigente_hasta)
        VALUES (
            fn_generar_id_historico('venta'),
            NEW.codigo,
            NEW.precio_venta,
            NEW.actualizado_en,
            NULL
        );

    -- CASO 2: Actualización de precios
    ELSIF TG_OP = 'UPDATE' THEN
        -- Si cambió el precio de compra:
        IF NEW.precio_compra IS DISTINCT FROM OLD.precio_compra THEN
            -- 1. Cerrar la vigencia del precio anterior
            UPDATE historico_precios_compra
            SET vigente_hasta = NEW.actualizado_en
            WHERE codigo_material = NEW.codigo
              AND vigente_hasta IS NULL;

            -- 2. Insertar el nuevo precio vigente
            INSERT INTO historico_precios_compra (id, codigo_material, precio, creado_en, vigente_hasta)
            VALUES (
                fn_generar_id_historico('compra'),
                NEW.codigo,
                NEW.precio_compra,
                NEW.actualizado_en,
                NULL
            );
        END IF;

        -- Si cambió el precio de venta:
        IF NEW.precio_venta IS DISTINCT FROM OLD.precio_venta THEN
            -- 1. Cerrar la vigencia del precio anterior
            UPDATE historico_precios_venta
            SET vigente_hasta = NEW.actualizado_en
            WHERE codigo_material = NEW.codigo
              AND vigente_hasta IS NULL;

            -- 2. Insertar el nuevo precio vigente
            INSERT INTO historico_precios_venta (id, codigo_material, precio, creado_en, vigente_hasta)
            VALUES (
                fn_generar_id_historico('venta'),
                NEW.codigo,
                NEW.precio_venta,
                NEW.actualizado_en,
                NULL
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_precios_aiu ON precios;
CREATE TRIGGER trg_precios_aiu
AFTER INSERT OR UPDATE ON precios
FOR EACH ROW
EXECUTE FUNCTION trg_gestionar_historico_precios();

-- 7. Trigger para garantizar la inmutabilidad de los históricos
--    Regla:
--    - id, codigo_material, precio y creado_en NUNCA se pueden modificar.
--    - Solo se permite actualizar 'vigente_hasta' si su valor actual es NULL (para cerrarlo).
--    - Una vez que 'vigente_hasta' tiene un valor asignado, la tupla es 100% inmutable.
CREATE OR REPLACE FUNCTION trg_historico_precios_inmutable()
RETURNS TRIGGER AS $$
BEGIN
    -- Si la tupla ya estaba cerrada (vigente_hasta NO es null), es totalmente intocable
    IF OLD.vigente_hasta IS NOT NULL THEN
        RAISE EXCEPTION 'Operación rechazada: el registro histórico ya está cerrado y es 100%% inmutable.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Los campos base nunca pueden cambiar
    IF NEW.id IS DISTINCT FROM OLD.id OR
       NEW.codigo_material IS DISTINCT FROM OLD.codigo_material OR
       NEW.precio IS DISTINCT FROM OLD.precio OR
       NEW.creado_en IS DISTINCT FROM OLD.creado_en THEN
        RAISE EXCEPTION 'Operación rechazada: los campos id, material, precio y fecha de creación del histórico son inmutables.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Solo se permite actualizar si se le asigna una fecha válida de cierre
    IF NEW.vigente_hasta IS NULL THEN
        RAISE EXCEPTION 'Operación rechazada: vigente_hasta solo puede actualizarse para establecer una fecha de cierre válida.'
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_hist_compra_inmutable ON historico_precios_compra;
CREATE TRIGGER trg_hist_compra_inmutable
BEFORE UPDATE ON historico_precios_compra
FOR EACH ROW
EXECUTE FUNCTION trg_historico_precios_inmutable();

DROP TRIGGER IF EXISTS trg_hist_venta_inmutable ON historico_precios_venta;
CREATE TRIGGER trg_hist_venta_inmutable
BEFORE UPDATE ON historico_precios_venta
FOR EACH ROW
EXECUTE FUNCTION trg_historico_precios_inmutable();

-- Comentarios explicativos en PostgreSQL
COMMENT ON TABLE precios IS 'Precios actuales vigentes de compra y venta por material';
COMMENT ON TABLE historico_precios_compra IS 'Histórico cronológico de precios de compra con control de vigencia e inmutabilidad';
COMMENT ON TABLE historico_precios_venta IS 'Histórico cronológico de precios de venta con control de vigencia e inmutabilidad';

-- 8. Trigger de Regla de Negocio:
--    Un material NO puede estar activo a menos que ya tenga precio de compra y de venta vigente registrado.
CREATE OR REPLACE FUNCTION trg_validar_material_activo_con_precios()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.activo = TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM precios
            WHERE codigo = NEW.codigo
              AND precio_compra IS NOT NULL
              AND precio_venta IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Operación rechazada: El material "%" no puede estar activo sin contar previamente con precios vigentes de compra y venta registrados.', NEW.nombre
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_materiales_validar_activo ON materiales;
CREATE TRIGGER trg_materiales_validar_activo
BEFORE INSERT OR UPDATE OF activo ON materiales
FOR EACH ROW
EXECUTE FUNCTION trg_validar_material_activo_con_precios();

