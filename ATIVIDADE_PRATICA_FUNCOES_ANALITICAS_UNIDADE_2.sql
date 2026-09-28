-- =====================================================================
-- ATIVIDADE PRATICA: FUNCOES ANALITICAS (OVER) - UNIDADE 2
-- Sistema de Vendas e Analise Comercial
-- Compativel com Oracle Database 23ai / Oracle APEX
-- Execute o DDL e o SEED antes deste arquivo.
--
-- Dica do professor: funcoes analiticas sao processadas por ultimo,
-- logo antes do ORDER BY final. Filtrar resultado de RANK/DENSE_RANK
-- exige CTE ou subquery (WHERE nao aceita funcao analitica).
-- =====================================================================

-- ---------------------------------------------------------------------
-- PARTE 1 - NUMERACAO E HISTORICO (ROW_NUMBER)
-- ---------------------------------------------------------------------

-- 1. Jornada de compras do cliente: numero_compra cronologico por cliente.
--    ROW_NUMBER atribui 1, 2, 3... as compras fechadas de cada cliente.
SELECT c.nome AS cliente,
       v.dt_venda,
       v.valor_liquido,
       ROW_NUMBER() OVER (
           PARTITION BY v.id_cliente
           ORDER BY v.dt_venda, v.id_venda
       ) AS numero_compra
FROM tb_cliente c
JOIN tb_venda v ON v.id_cliente = c.id_cliente
WHERE v.status = 'FECHADA'
ORDER BY cliente, numero_compra;

-- ---------------------------------------------------------------------
-- PARTE 2 - COMPETICOES E AGRUPAMENTOS ANALITICOS
--            (DENSE_RANK + PARTITION BY)
-- ---------------------------------------------------------------------

-- 2. Ranking mensal de vendedores: pódio reiniciado a cada mês.
--    CTE calcula o total por vendedor/mes; DENSE_RANK particiona por mes.
WITH receita_vendedor_mes AS (
    SELECT TRUNC(v.dt_venda, 'MM') AS mes_ref,
           ven.nome AS vendedor,
           SUM(v.valor_liquido) AS receita_mensal
    FROM tb_venda v
    JOIN tb_vendedor ven ON ven.id_vendedor = v.id_vendedor
    WHERE v.status = 'FECHADA'
    GROUP BY TRUNC(v.dt_venda, 'MM'), ven.nome
)
SELECT mes_ref,
       vendedor,
       receita_mensal,
       DENSE_RANK() OVER (
           PARTITION BY mes_ref
           ORDER BY receita_mensal DESC
       ) AS posicao_ranking
FROM receita_vendedor_mes
ORDER BY mes_ref, posicao_ranking, vendedor;

-- 3. Os 2 produtos mais vendidos por categoria (carros-chefes).
--    WHERE nao aceita DENSE_RANK: filtro aplicado em CTE externa.
WITH quantidade_por_categoria AS (
    SELECT cat.nome AS categoria,
           p.nome AS produto,
           SUM(i.quantidade) AS total_vendido
    FROM tb_venda_item i
    JOIN tb_produto p ON p.id_produto = i.id_produto
    JOIN tb_categoria cat ON cat.id_categoria = p.id_categoria
    JOIN tb_venda v ON v.id_venda = i.id_venda
    WHERE v.status = 'FECHADA'
    GROUP BY cat.nome, p.nome
),
ranking_produtos AS (
    SELECT categoria,
           produto,
           total_vendido,
           DENSE_RANK() OVER (
               PARTITION BY categoria
               ORDER BY total_vendido DESC
           ) AS posicao_ranking
    FROM quantidade_por_categoria
)
SELECT categoria,
       produto,
       total_vendido,
       posicao_ranking
FROM ranking_produtos
WHERE posicao_ranking <= 2
ORDER BY categoria, posicao_ranking, produto;

-- 3.1 Bonus: diferenca entre RANK e DENSE_RANK com empates.
--     RANK pula numeros apos empate (1, 1, 3); DENSE_RANK nao (1, 1, 2).
WITH receita_vendedor_mes AS (
    SELECT TRUNC(v.dt_venda, 'MM') AS mes_ref,
           ven.nome AS vendedor,
           SUM(v.valor_liquido) AS receita_mensal
    FROM tb_venda v
    JOIN tb_vendedor ven ON ven.id_vendedor = v.id_vendedor
    WHERE v.status = 'FECHADA'
    GROUP BY TRUNC(v.dt_venda, 'MM'), ven.nome
)
SELECT mes_ref,
       vendedor,
       receita_mensal,
       RANK() OVER (
           PARTITION BY mes_ref
           ORDER BY receita_mensal DESC
       ) AS posicao_rank,
       DENSE_RANK() OVER (
           PARTITION BY mes_ref
           ORDER BY receita_mensal DESC
       ) AS posicao_dense_rank
FROM receita_vendedor_mes
ORDER BY mes_ref, posicao_rank, vendedor;

-- ---------------------------------------------------------------------
-- PARTE 3 - INDICADORES DE NEGOCIO AVANCADOS (MATEMATICA COM OVER)
-- ---------------------------------------------------------------------

-- 4. Participacao no faturamento (market share interno) por vendedor.
--    SUM(receita) OVER () entrega o total geral da empresa em cada linha.
WITH faturamento_por_vendedor AS (
    SELECT ven.nome AS vendedor,
           SUM(v.valor_liquido) AS faturamento
    FROM tb_vendedor ven
    JOIN tb_venda v ON v.id_vendedor = ven.id_vendedor
    WHERE v.status = 'FECHADA'
    GROUP BY ven.nome
)
SELECT vendedor,
       faturamento,
       ROUND(SUM(faturamento) OVER (), 2) AS faturamento_empresa,
       ROUND(faturamento / SUM(faturamento) OVER () * 100, 2) AS participacao_pct
FROM faturamento_por_vendedor
ORDER BY faturamento DESC;

-- 5. Termometro de vendas: cada venda vs media geral da empresa.
--    diferenca_media positiva = acima do padrao; negativa = abaixo.
SELECT id_venda,
       valor_liquido,
       ROUND(AVG(valor_liquido) OVER (), 2) AS media_geral,
       ROUND(valor_liquido - AVG(valor_liquido) OVER (), 2) AS diferenca_media
FROM tb_venda
ORDER BY diferenca_media DESC;
