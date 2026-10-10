-- =============================================================================
-- Módulo 01: Tabla de Usuarios
-- Descripción: Gestión de usuarios del sistema (Clientes y Administradores).
--              Incluye credenciales de acceso: 'usuario' y 'password_hash'.
-- =============================================================================

CREATE TABLE IF NOT EXISTS usuarios (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    usuario VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255),
    admin BOOLEAN NOT NULL DEFAULT FALSE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Migraciones seguras si la tabla ya existía previamente
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE usuarios DROP COLUMN IF EXISTS email;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS usuario VARCHAR(100) UNIQUE;
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);

-- Comentarios explicativos en el catálogo de PostgreSQL
COMMENT ON TABLE usuarios IS 'Almacena usuarios del sistema: administradores (PC) y clientes (Móvil)';
COMMENT ON COLUMN usuarios.id IS 'Identificador único incremental';
COMMENT ON COLUMN usuarios.usuario IS 'Nombre de usuario único para autenticación';
COMMENT ON COLUMN usuarios.password_hash IS 'Contraseña hasheada con bcrypt para acceso seguro';
COMMENT ON COLUMN usuarios.admin IS 'Bandera de rol: true para administradores, false para clientes';
COMMENT ON COLUMN usuarios.activo IS 'Estado del usuario: true (activo), false (desactivado)';
