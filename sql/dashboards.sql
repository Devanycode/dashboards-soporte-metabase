/* 
=============================================================
HERRAMIENTAS:
MySQL
Docker
Metabase

BASE DE DATOS:
tickets

DESCRIPCIÓN:
Este archivo contiene todas las consultas SQL
utilizadas para construir los dashboards del proyecto.

AUTOR: 
Samuel Devany Rincón Ceballos 
Fecha: 
2026-07

===============================================================
*/
USE tickets;



-- ==================================
-- DASHBOARD DE SOPORTE 
-- ==================================
-- Función: Con este Dashboard se busca medir la calidad de la atención y resolución de problemas del grupo de soporte
-- Base de datos: tickets
-- Tablas usadas: surveys_answer, surveys_option, tickets, auth_user, appointments
-- Tablas que reaccionan a filtros:
	-- Filtro de FECHA:
		/*  - Indice de Satisfacción general (CSAT)
			- Nivel de Resolución (Efectividad)
            - Tiempo Medio de Resolución General
            - Tickets Resueltos por Agente
            - Tiempo Medio de Resolución (MTTR) por Agente
            - MTTR por Tipo de Entidad (EPS vs IPS)
            - Tendencia Tiempo de Resolución
            - Satisfacción del Servicio
            - Efectividad del Soporte (Resolución Final)
            - Índice del Esfuerzo del Cliente (CES)
            - Comentarios y Retroalimentación Abierta
		*/
	-- Filtro de ID:
		/*  - Tickets Resueltos por Agente
			- Tiempo Medio de Resolución (MTTR) por Agente
		*/

-- Consultas reutilizadas para varios KPIs:
-- {{#107-agentes}} 
/* Con esta consulta, se obtienen los datos del id del agente y el nombre completo de este */
SELECT
    id,
    CONCAT(first_name, ' ', last_name) AS nombre_completo
FROM auth_user
WHERE id NOT IN (1, 2, 3, 13);

-- {{#137-meses-en-espanol}}
/*Con esta consulta se obtienen el número del mes y el nombre de los meses en español*/
SELECT MONTH(created_at) AS mes,
	CASE MONTH(created_at)
        WHEN 1 THEN 'Enero'
        WHEN 2 THEN 'Febrero'
        WHEN 3 THEN 'Marzo'
        WHEN 4 THEN 'Abril'
        WHEN 5 THEN 'Mayo'
        WHEN 6 THEN 'Junio'
        WHEN 7 THEN 'Julio'
        WHEN 8 THEN 'Agosto'
        WHEN 9 THEN 'Septiembre'
        WHEN 10 THEN 'Octubre'
        WHEN 11 THEN 'Noviembre'
        WHEN 12 THEN 'Diciembre'
	END AS nombre_mes
FROM tickets
GROUP BY mes, nombre_mes
ORDER BY mes, nombre_mes;


-- ------
-- KPIs
-- ------

-- KPI 1.
-- Índice de Satisfacción General (CSAT)
SELECT
    ROUND( 
		SUM(CASE 
				WHEN sa.option_selected_id IN (1, 2) 
                THEN 1 ELSE 0 
			END) / 
		COUNT(*) * 100,
	2) AS porcentaje_satisfaccion
FROM tickets.surveys_answer sa
JOIN surveys_option so ON sa.option_selected_id = so.id
WHERE sa.question_id = 1;
-- Filtro: {{surveys_answer.created_at}}


-- KPI 2.
-- Nivel de Resolución (Efectividad)
SELECT
    ROUND( 
		SUM(CASE 
				WHEN sa.option_selected_id = 5 
                THEN 1 ELSE 0 
			END) / 
		COUNT(*) * 100,
	2) AS porcentaje_satisfaccion
FROM tickets.surveys_answer sa
JOIN surveys_option so ON sa.option_selected_id = so.id
WHERE sa.question_id = 2;
-- Filtro: {{surveys_answer.created_at}}


-- KPI 3.
-- Tiempo Medio de Resolución General
WITH RECURSIVE Fechas AS (
    SELECT 
        id, 
        created_at, 
        completed_at, 
        DATE(created_at) AS dia
    FROM tickets
    WHERE completed_at IS NOT NULL
		-- AND modified_by_id <> 1  En caso de no querer incluir el bot en el resultado
        -- [[AND {{created_at}}]] IMP: Filtro: {{tickets_created_at}}

    UNION ALL

    SELECT 
        id, 
        created_at, 
        completed_at, 
        dia + INTERVAL 1 DAY
    FROM Fechas
    WHERE dia < DATE(completed_at)
),
Horario AS (
    SELECT
        id, created_at, completed_at, dia,
        CASE DAYOFWEEK(dia)                                    -- 1=Domingo, 7=Sábado
            WHEN 1 THEN NULL
            ELSE CAST(CONCAT(dia, ' 08:00:00') AS DATETIME)
        END AS Apertura,
        CASE DAYOFWEEK(dia)
            WHEN 1 THEN NULL
            WHEN 7 THEN CAST(CONCAT(dia, ' 12:00:00') AS DATETIME)
            ELSE CAST(CONCAT(dia, ' 17:00:00') AS DATETIME)
        END AS Cierre
    FROM Fechas
),
MinutosPorDia AS (
    SELECT
        id,
        GREATEST(
            TIMESTAMPDIFF(MINUTE, GREATEST(Apertura, created_at), LEAST(Cierre, completed_at)),
            0
        ) AS Minutos
    FROM Horario
    WHERE Apertura IS NOT NULL   -- descarta domingos
),
TotalMinutos AS (
	SELECT id, SUM(Minutos) AS TotalMinutos
    FROM MinutosPorDia
    GROUP BY id
)
SELECT ROUND(AVG(TotalMinutos) / 60.0, 2) AS PromedioHorasLaborales
FROM TotalMinutos



-- ---------
-- Gráficas
-- ---------

-- GRÁFICA 1.
-- Tickets Resueltos por Agente
WITH agentes AS (-- {{#107-agentes}}
-- la siguiente consulta es exactamente: {{#107-agentes}}
SELECT
    id,
    CONCAT(first_name, ' ', last_name) AS nombre_completo
FROM auth_user
WHERE id NOT IN (1, 2, 3, 13)
)
SELECT 
	a.nombre_completo AS agente,
    COUNT(*) AS tickets_completados
FROM agentes a
JOIN tickets t ON t.modified_by_id = a.id
WHERE t.state = 'COMPLETADO'
	AND t.completed_at IS NOT NULL 
GROUP BY a.id, a.nombre_completo
HAVING tickets_completados > 0
ORDER BY tickets_completados DESC;
-- Filtros: {{tickets.created_at}} {{id -> auth_user.id}} 


-- GRÁFICA 2.
-- Tiempo Medio de Resolución (MTTR) por Agente
SELECT 
	u.id,
	CASE 
		WHEN u.first_name LIKE '%Chatbot%' THEN u.first_name 
        ELSE CONCAT(u.first_name, ' ', u.last_name) 
	END AS agente,
    ROUND(
		AVG(TIMESTAMPDIFF(hour, t.created_at, t.completed_at)),
        2
	) AS tiempo_resolucion_horas
FROM auth_user u
JOIN tickets t
ON t.modified_by_id = u.id
WHERE t.state = 'COMPLETADO'
  AND t.completed_at IS NOT NULL
  AND u.id != 1
GROUP BY u.id, agente
ORDER BY tiempo_resolucion_horas DESC, agente;
-- Filtros: {{auth_user.id}} {{tickets-created_at}}


-- GRÁFICA 3.
-- MTTR por Tipo de Entidad (EPS vs IPS)
SELECT entity_type,
	ROUND(
		AVG(TIMESTAMPDIFF(hour, created_at, completed_at)),
        2
	) AS tiempo_resolucion_horas
FROM appointments 
WHERE completed_at IS NOT NULL
GROUP BY entity_type
HAVING COUNT(*) > 5
ORDER BY tiempo_resolucion_horas DESC;
-- Filtro: {{appointments.created_at}}


-- GRÁFICA 4.
-- Tendencia Tiempo de Resolución 
WITH meses AS (-- {{#137-meses-en-espanol}}
-- La siguiente consulta es exactamente {{#137-meses-en-español}}
SELECT MONTH(created_at) AS mes,
	CASE MONTH(created_at)
        WHEN 1 THEN 'Enero'
        WHEN 2 THEN 'Febrero'
        WHEN 3 THEN 'Marzo'
        WHEN 4 THEN 'Abril'
        WHEN 5 THEN 'Mayo'
        WHEN 6 THEN 'Junio'
        WHEN 7 THEN 'Julio'
        WHEN 8 THEN 'Agosto'
        WHEN 9 THEN 'Septiembre'
        WHEN 10 THEN 'Octubre'
        WHEN 11 THEN 'Noviembre'
        WHEN 12 THEN 'Diciembre'
	END AS nombre_mes
FROM tickets
GROUP BY mes, nombre_mes
ORDER BY mes, nombre_mes
)
SELECT 
	m.mes, 
	m.nombre_mes, 
	ROUND(
		AVG(
			TIMESTAMPDIFF(hour, created_at, completed_at)
		),
		2
	) AS tiempo_resolucion
FROM tickets t
JOIN meses m ON MONTH(t.created_at) = m.mes
GROUP BY m.mes, m.nombre_mes
ORDER BY m.mes, m.nombre_mes;
-- Filtro: {{tickets.created_at}}


-- GRÁFICA 5.
-- Satisfacción del Servicio 
WITH question_1 AS (
SELECT
    so.text AS respuesta,
    COUNT(*) AS conteo
FROM surveys_answer sa
JOIN surveys_option so ON sa.option_selected_id = so.id
WHERE sa.question_id = 1
GROUP BY respuesta
-- IMP:
-- Filtro {{surveys_answer.created_at}}
)
SELECT 
    respuesta, 
    ROUND(
		conteo / SUM(conteo) OVER() * 100,
		2
    )  AS porcentaje_respuesta
FROM question_1
GROUP BY respuesta
ORDER BY porcentaje_respuesta DESC;


-- GRÁFICA 6.
-- Efectividad del Soporte (Resolución Final)
WITH question_2 AS (
SELECT
    so.text AS respuesta,
    COUNT(*) AS conteo
FROM tickets.surveys_answer sa
JOIN surveys_option so ON sa.option_selected_id = so.id
WHERE sa.question_id = 2
GROUP BY respuesta
-- IMP:
-- Filtro: {{survey_answer.created_at}}
) 
SELECT 
    respuesta, 
    ROUND(
		conteo / SUM(conteo) OVER() * 100,
		2
    )  AS porcentaje_respuesta
FROM question_2
GROUP BY respuesta
ORDER BY porcentaje_respuesta DESC;


-- GRÁFICA 7.
-- Índice de Esfuerzo del Cliente (CES)
WITH question_3 AS (
SELECT
    so.text AS respuesta,
    COUNT(*) AS conteo
FROM tickets.surveys_answer sa
JOIN surveys_option so ON sa.option_selected_id = so.id
WHERE sa.question_id = 3
GROUP BY respuesta
-- IMP:
-- Filtro: {{surveys_answer.created_at}}
)
SELECT 
    respuesta, 
    ROUND(
		conteo / SUM(conteo) OVER() * 100,
		2
    )  AS porcentaje_respuesta
FROM question_3
GROUP BY respuesta
ORDER BY porcentaje_respuesta DESC;


-- GRÁFICA 8.
-- Comentarios y Retroalimentación Abierta 
SELECT
    text_answer,
    created_at
FROM tickets.surveys_answer sa
JOIN surveys_question sq ON sa.question_id = sq.id
WHERE sa.question_id = 4
	AND sq.text IS NOT NULL 
ORDER BY created_at DESC LIMIT 10;
-- Filtro: {{surveys_answer.created_at}}

-- ------------------------------------------------------------------------------


-- ==================================
-- DASHBOARD EJECUTIVO 
-- ==================================

-- Función: Con este Dashboard se busca
-- Base de datos: tickets
-- Tablas usadas: tickets, appointments
-- Gráficas que reaccionan al filtro de fecha:
	/*  - Tiempo Medio de Resolución General
		- Porcentaje de Retención de Bot
        - Tickets por Entidad
        - Tickets por Categoría
	*/

-- ------------
-- KPIs
-- ------------

-- KPI 1.
-- Tickets Mes Previo a Refencia
WITH 
	parametros AS (
    SELECT COALESCE([[ {{fecha}}, ]] DATE_SUB(CURDATE(), INTERVAL 1 MONTH)) AS fecha_ref  -- Aquí esta el filtro de fecha opcional
),
	resumen AS (
    SELECT
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(p.fecha_ref, '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(DATE_ADD(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_referencia,
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(DATE_SUB(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(p.fecha_ref, '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_previo
    FROM tickets t
    CROSS JOIN parametros p
)
SELECT conteo_mes_previo
FROM resumen

-- KPI 2.
-- Tickets Mes de Referencia
WITH 
	parametros AS (
    SELECT COALESCE([[ {{fecha}}, ]] DATE_SUB(CURDATE(), INTERVAL 1 MONTH)) AS fecha_ref  -- Aquí está el filtro de fecha opcional
),
	resumen AS (
    SELECT
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(p.fecha_ref, '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(DATE_ADD(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_referencia,
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(DATE_SUB(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(p.fecha_ref, '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_previo
    FROM tickets t
    CROSS JOIN parametros p
)
SELECT conteo_mes_referencia
FROM resumen


-- KPI 3.
-- Diferencia entre Meses 
WITH 
	parametros AS (
    SELECT COALESCE([[ {{fecha}}, ]] DATE_SUB(CURDATE(), INTERVAL 1 MONTH)) AS fecha_ref  -- Aquí está el filtro de fecha opcional
),
	resumen AS (
    SELECT
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(p.fecha_ref, '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(DATE_ADD(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_referencia,
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(DATE_SUB(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(p.fecha_ref, '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_previo
    FROM tickets t
    CROSS JOIN parametros p
)
SELECT conteo_mes_referencia - conteo_mes_previo FROM resumen


-- KPI 4.
-- Variación entre Meses
WITH 
	parametros AS (
    SELECT COALESCE([[ {{fecha}}, ]] DATE_SUB(CURDATE(), INTERVAL 1 MONTH)) AS fecha_ref  -- Aqui está el filtro de fecha opcional
),
	resumen AS (
    SELECT
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(p.fecha_ref, '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(DATE_ADD(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_referencia,
        SUM(CASE 
            WHEN t.created_at >= DATE_FORMAT(DATE_SUB(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01') 
             AND t.created_at < DATE_FORMAT(p.fecha_ref, '%Y-%m-01')
            THEN 1 ELSE 0 
        END) AS conteo_mes_previo
    FROM tickets t
    CROSS JOIN parametros p
)
SELECT ROUND(100 * ( conteo_mes_referencia - conteo_mes_previo ) / NULLIF(conteo_mes_previo, 0), 
			2) AS variacion
FROM resumen


-- KPI 5.
-- Tiempo Medio de Resolución General (también en dashboard de soporte)
WITH RECURSIVE Fechas AS (
    SELECT 
        id, 
        created_at, 
        completed_at, 
        DATE(created_at) AS dia
    FROM tickets
    WHERE completed_at IS NOT NULL
		-- AND modified_by_id <> 1  En caso de no querer incluir el bot en el resultado
        -- [[AND {{created_at}}]] IMP: Filtro: {{tickets_created_at}}

    UNION ALL

    SELECT 
        id, 
        created_at, 
        completed_at, 
        dia + INTERVAL 1 DAY
    FROM Fechas
    WHERE dia < DATE(completed_at)
),
Horario AS (
    SELECT
        id, created_at, completed_at, dia,
        CASE DAYOFWEEK(dia)                                    -- 1=Domingo, 7=Sábado
            WHEN 1 THEN NULL
            ELSE CAST(CONCAT(dia, ' 08:00:00') AS DATETIME)
        END AS Apertura,
        CASE DAYOFWEEK(dia)
            WHEN 1 THEN NULL
            WHEN 7 THEN CAST(CONCAT(dia, ' 12:00:00') AS DATETIME)
            ELSE CAST(CONCAT(dia, ' 17:00:00') AS DATETIME)
        END AS Cierre
    FROM Fechas
),
MinutosPorDia AS (
    SELECT
        id,
        GREATEST(
            TIMESTAMPDIFF(MINUTE, GREATEST(Apertura, created_at), LEAST(Cierre, completed_at)),
            0
        ) AS Minutos
    FROM Horario
    WHERE Apertura IS NOT NULL   -- descarta domingos
),
TotalMinutos AS (
	SELECT id, SUM(Minutos) AS TotalMinutos
    FROM MinutosPorDia
    GROUP BY id
)
SELECT ROUND(AVG(TotalMinutos) / 60.0, 2) AS PromedioHorasLaborales
FROM TotalMinutos



-- KPI 6.
-- Porcentaje Retención de Bot
WITH resolucion AS (
SELECT 
	   SUM(CASE WHEN modified_by_id = 1 THEN 1 ELSE 0
		   END) AS resolucion_bot,
           
	   SUM(CASE WHEN modified_by_id IS NOT NULL THEN 1 ELSE 0
		   END) AS resolucion_total
FROM tickets
)
SELECT 
	(resolucion_bot / resolucion_total) AS porcentaje_retencion_bot
FROM resolucion;
-- Filtro: {{tickets.created_at}}


-- -------------
-- Gráficas
-- -------------

-- GRÁFICA 1.
-- Tickets Creados:  Mes Previo vs Mes de Referencia
WITH parametros AS (
    SELECT COALESCE(
        [[ {{fecha}}, ]]   -- Aquí está el filtro de fecha opcional
        DATE_SUB(CURDATE(), INTERVAL 1 MONTH)
    ) AS fecha_ref
)
SELECT
    DATE_FORMAT(t.created_at, '%Y-%m-01') AS primer_dia_mes,
    m.mes,
    m.nombre_mes,
    COUNT(*) AS conteo
FROM tickets t
JOIN {{#137-meses-en-espanol}} m ON m.mes = MONTH(t.created_at)
CROSS JOIN parametros p
WHERE 
    t.created_at >= DATE_FORMAT(DATE_SUB(p.fecha_ref, INTERVAL 1 MONTH), '%Y-%m-01')
    AND t.created_at <= DATE_FORMAT(p.fecha_ref + INTERVAL 1 MONTH, '%Y-%m-01')
GROUP BY primer_dia_mes, m.mes, m.nombre_mes
ORDER BY primer_dia_mes, m.mes, m.nombre_mes


-- GRÁFICA 2.
-- Tickets Creados Año Anterior vs Año Actual
SELECT 
	MONTH(created_at) AS numero_mes,
    CASE MONTH(created_at)
        WHEN 1 THEN 'Enero'
        WHEN 2 THEN 'Febrero'
        WHEN 3 THEN 'Marzo'
        WHEN 4 THEN 'Abril'
        WHEN 5 THEN 'Mayo'
        WHEN 6 THEN 'Junio'
        WHEN 7 THEN 'Julio'
        WHEN 8 THEN 'Agosto'
        WHEN 9 THEN 'Septiembre'
        WHEN 10 THEN 'Octubre'
        WHEN 11 THEN 'Noviembre'
        WHEN 12 THEN 'Diciembre'
    END AS nombre_mes,
    SUM(
		CASE WHEN YEAR(created_at) = YEAR(CURDATE()) THEN 1 ELSE 0 
	END) AS año_actual,
    SUM(
		CASE WHEN YEAR(created_at) = YEAR(CURDATE() - INTERVAL 1 YEAR)  THEN 1 ELSE 0 
	END) AS año_anterior	
FROM tickets
GROUP BY numero_mes, nombre_mes
ORDER BY numero_mes;


-- GRÁFICA 4.
-- Tickets por entidad
SELECT 
	entity_type AS 'Tickets por Entidad',
	COUNT(*) AS conteo
FROM appointments
GROUP BY entity_type
ORDER BY COUNT(*) DESC;
-- Filtro: {{appointments}}


-- GRÁFICA 5.
-- Tickets por Categoría
SELECT description,
	COUNT(*) AS conteo
FROM tickets
GROUP BY description
ORDER BY conteo DESC;
-- Filtro: {{tickets.created_at}}


-- GRÁFICA 6.
-- Horas de Mayor Actividad
SELECT  
	HOUR(created_at) AS hora_orden,
    DATE_FORMAT(created_at, '%l %p') AS hora_creacion,
	COUNT(*) AS conteo
FROM tickets
GROUP BY hora_orden, hora_creacion
ORDER BY hora_orden ASC;
-- Filtro: {{tickets.created_at}}




