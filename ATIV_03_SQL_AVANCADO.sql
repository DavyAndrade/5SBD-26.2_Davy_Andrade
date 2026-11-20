-- =====================================================================
-- ATIVIDADE PRATICA: SQL AVANCADO E ANALISE COMERCIAL - UNIDADE 1
-- Sistema de Vendas e Analise Comercial
-- Compativel com Oracle Database 23ai / Oracle APEX
-- Execute o DDL e o SEED antes deste arquivo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PARTE 1 - REVISAO DE JOINS E AGRUPAMENTOS
-- ---------------------------------------------------------------------

-- 1. Desempenho de vendas por vendedor.
SELECT ven.nome AS vendedor,
       SUM(v.valor_liquido) AS total_vendido
FROM tb_vendedor ven
JOIN tb_venda v ON v.id_vendedor = ven.id_vendedor
WHERE v.status = 'FECHADA'
GROUP BY ven.nome
ORDER BY total_vendido DESC;

-- 2. Historico de compras do cliente, incluindo vendas abertas e canceladas.
SELECT c.nome AS cliente,
       v.dt_venda,
       v.valor_liquido,
       v.status
FROM tb_cliente c
JOIN tb_venda v ON v.id_cliente = c.id_cliente
ORDER BY c.nome, v.dt_venda;

-- 3. Melhor cliente considerando somente compras fechadas.
SELECT c.nome AS cliente,
       SUM(v.valor_liquido) AS faturamento_total
FROM tb_cliente c
JOIN tb_venda v ON v.id_cliente = c.id_cliente
WHERE v.status = 'FECHADA'
GROUP BY c.nome
ORDER BY faturamento_total DESC
FETCH FIRST 1 ROW ONLY;

-- ---------------------------------------------------------------------
-- PARTE 2 - SUBQUERIES, EXISTS, IN E CASE WHEN
-- ---------------------------------------------------------------------

-- 4. Vendas fechadas acima da media geral de vendas fechadas.
SELECT id_venda,
       dt_venda,
       valor_liquido
FROM tb_venda
WHERE status = 'FECHADA'
  AND valor_liquido > (
      SELECT AVG(valor_liquido)
      FROM tb_venda
      WHERE status = 'FECHADA'
  )
ORDER BY valor_liquido DESC;

-- 5. Produtos ativos sem qualquer registro de venda.
SELECT p.nome AS produto,
       p.sku
FROM tb_produto p
WHERE p.ativo = 'S'
  AND NOT EXISTS (
      SELECT 1
      FROM tb_venda_item i
      WHERE i.id_produto = p.id_produto
  )
ORDER BY p.nome;

-- 6. Classificacao comercial dos clientes por faturamento fechado.
SELECT c.nome AS cliente,
       SUM(v.valor_liquido) AS faturamento,
       CASE
           WHEN SUM(v.valor_liquido) > 10000 THEN 'Ouro'
           WHEN SUM(v.valor_liquido) >= 2000 THEN 'Prata'
           ELSE 'Bronze'
       END AS categoria_cliente
FROM tb_cliente c
JOIN tb_venda v ON v.id_cliente = c.id_cliente
WHERE v.status = 'FECHADA'
GROUP BY c.nome
ORDER BY faturamento DESC;

-- 6.1 Clientes que possuem pelo menos uma venda fechada (uso de IN).
SELECT c.nome AS cliente,
       c.email
FROM tb_cliente c
WHERE c.id_cliente IN (
    SELECT v.id_cliente
    FROM tb_venda v
    WHERE v.status = 'FECHADA'
)
ORDER BY c.nome;

-- ---------------------------------------------------------------------
-- PARTE 3 - CTE (WITH)
-- ---------------------------------------------------------------------

-- 7. Receita mensal de vendas fechadas.
WITH receita_mensal AS (
    SELECT TRUNC(dt_venda, 'MM') AS mes_ref,
           SUM(valor_liquido) AS receita
    FROM tb_venda
    WHERE status = 'FECHADA'
    GROUP BY TRUNC(dt_venda, 'MM')
)
SELECT mes_ref,
       receita
FROM receita_mensal
ORDER BY mes_ref;

-- 8. Cinco produtos com maior quantidade vendida.
WITH quantidade_por_produto AS (
    SELECT p.nome AS produto,
           SUM(i.quantidade) AS total_vendido
    FROM tb_produto p
    JOIN tb_venda_item i ON i.id_produto = p.id_produto
    GROUP BY p.nome
)
SELECT produto,
       total_vendido
FROM quantidade_por_produto
ORDER BY total_vendido DESC, produto
FETCH FIRST 5 ROWS ONLY;

-- =====================================================================
-- EXERCICIOS POR NIVEL - GABARITO
-- =====================================================================

-- ---------------------------------------------------------------------
-- NIVEL SIMPLES
-- ---------------------------------------------------------------------

-- 1. Listagem de clientes ativos.
SELECT nome,
       email,
       telefone
FROM tb_cliente
WHERE ativo = 'S'
ORDER BY nome;

-- 2. Vendas fechadas realizadas pelo canal APP.
SELECT id_venda,
       dt_venda,
       valor_liquido
FROM tb_venda
WHERE canal = 'APP'
  AND status = 'FECHADA'
ORDER BY dt_venda;

-- 3. Catalogo de produtos e categorias.
SELECT p.nome AS produto,
       p.sku,
       c.nome AS categoria
FROM tb_produto p
JOIN tb_categoria c ON c.id_categoria = p.id_categoria
ORDER BY c.nome, p.nome;

-- 4. Quantidade de vendedores cadastrados.
SELECT COUNT(*) AS total_vendedores
FROM tb_vendedor;

-- 5. Produtos ativos ordenados do maior preco para o menor.
SELECT nome AS produto,
       preco_unit
FROM tb_produto
WHERE ativo = 'S'
ORDER BY preco_unit DESC, nome;

-- ---------------------------------------------------------------------
-- NIVEL INTERMEDIARIO
-- ---------------------------------------------------------------------

-- 6. Faturamento por canal, considerando vendas fechadas.
SELECT canal,
       SUM(valor_liquido) AS faturamento_total
FROM tb_venda
WHERE status = 'FECHADA'
GROUP BY canal
ORDER BY faturamento_total DESC;

-- 7. Ticket medio de vendas fechadas por vendedor.
SELECT ven.nome AS vendedor,
       ROUND(AVG(v.valor_liquido), 2) AS ticket_medio
FROM tb_vendedor ven
JOIN tb_venda v ON v.id_vendedor = ven.id_vendedor
WHERE v.status = 'FECHADA'
GROUP BY ven.nome
ORDER BY ticket_medio DESC;

-- 8. Clientes sem qualquer compra registrada.
SELECT c.nome,
       c.email
FROM tb_cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM tb_venda v
    WHERE v.id_cliente = c.id_cliente
)
ORDER BY c.nome;

-- 9. Vendas fechadas acima da media, com nome do cliente.
SELECT v.id_venda,
       c.nome AS cliente,
       v.valor_liquido
FROM tb_venda v
JOIN tb_cliente c ON c.id_cliente = v.id_cliente
WHERE v.status = 'FECHADA'
  AND v.valor_liquido > (
      SELECT AVG(valor_liquido)
      FROM tb_venda
      WHERE status = 'FECHADA'
  )
ORDER BY v.valor_liquido DESC;

-- 10. Faixa de preco dos produtos ativos.
SELECT nome AS produto,
       preco_unit,
       CASE
           WHEN preco_unit < 50 THEN 'BARATO'
           WHEN preco_unit <= 200 THEN 'MEDIO'
           ELSE 'CARO'
       END AS faixa_preco
FROM tb_produto
WHERE ativo = 'S'
ORDER BY preco_unit DESC;

-- ---------------------------------------------------------------------
-- NIVEL AVANCADO
-- ---------------------------------------------------------------------

-- 11. Numeracao cronologica das compras fechadas de cada cliente.
SELECT c.nome AS cliente,
       v.dt_venda,
       v.valor_liquido,
       ROW_NUMBER() OVER (
           PARTITION BY c.id_cliente
           ORDER BY v.dt_venda, v.id_venda
       ) AS numero_compra
FROM tb_cliente c
JOIN tb_venda v ON v.id_cliente = c.id_cliente
WHERE v.status = 'FECHADA'
ORDER BY c.nome, numero_compra;

-- 12. Participacao percentual de cada vendedor no faturamento fechado.
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
       ROUND(faturamento / SUM(faturamento) OVER () * 100, 2) AS percentual_faturamento
FROM faturamento_por_vendedor
ORDER BY faturamento DESC;

-- 13. Ranking mensal de vendedores por receita fechada.
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

-- 14. Diferenca de cada venda para media geral de todas as vendas.
SELECT id_venda,
       valor_liquido,
       ROUND(valor_liquido - AVG(valor_liquido) OVER (), 2) AS diferenca_para_media
FROM tb_venda
ORDER BY id_venda;

-- 15. Tres produtos mais vendidos em vendas fechadas.
WITH quantidade_por_produto AS (
    SELECT p.nome AS produto,
           SUM(i.quantidade) AS total_vendido
    FROM tb_produto p
    JOIN tb_venda_item i ON i.id_produto = p.id_produto
    JOIN tb_venda v ON v.id_venda = i.id_venda
    WHERE v.status = 'FECHADA'
    GROUP BY p.nome
), ranking_produtos AS (
    SELECT produto,
           total_vendido,
           DENSE_RANK() OVER (ORDER BY total_vendido DESC) AS posicao_ranking
    FROM quantidade_por_produto
)
SELECT produto,
       total_vendido,
       posicao_ranking
FROM ranking_produtos
WHERE posicao_ranking <= 3
ORDER BY posicao_ranking, produto;
