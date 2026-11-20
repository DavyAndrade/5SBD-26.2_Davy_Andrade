# 5SBD — Unidade 4: Views como Camada de Abstração, Segurança e Reuso

Views (visões) são tabelas virtuais: o Oracle guarda no dicionário apenas a query definidora, nada de dados. Consultar uma view é executar essa query sob demanda. Três papéis que a unidade cobra: **abstrair o JOIN físico**, **restringir acesso (segurança/LGPD)** e **centralizar a regra analítica pro BI**.

> Todos os SQLs abaixo foram executados e conferidos em um Oracle Free 26ai real (container Docker `gvenzl/oracle-free`), com o `SISTEMA_VENDAS_DDL_V1.0.sql` e o `SISTEMA_VENDAS_SEED_V1.0.sql` carregados. Os retornos citados são os da execução real.

---

## Parte 1 — Abstração Operacional

### Questão 1: View de Resumo de Vendas (V_VENDAS_RESUMO)

```sql
CREATE OR REPLACE VIEW V_VENDAS_RESUMO AS
SELECT v.id_venda,
       v.dt_venda,
       v.status,
       v.canal,
       c.nome   AS nome_cliente,
       ven.nome AS nome_vendedor,
       v.valor_liquido
FROM tb_venda v
JOIN tb_cliente c    ON c.id_cliente    = v.id_cliente
JOIN tb_vendedor ven ON ven.id_vendedor = v.id_vendedor
WITH READ ONLY;

SELECT * FROM V_VENDAS_RESUMO WHERE ROWNUM <= 5;
```

Retorno do Oracle (5 primeiras linhas):

```
 ID_VENDA DT_VENDA           STATUS            CANAL     NOME_CLIENTE        NOME_VENDEDOR      VALOR_LIQUIDO
-------- ------------------- ----------------- --------- ------------------- ------------------ -------------
       1 17-MAY-26           FECHADA           SITE      Andreia Santos      Patricia Ramos           1476.50
       2 08-MAY-26           ABERTA            TELEFONE  Gabriel Costa       Regina Duarte           12099.00
       3 07-MAY-26           FECHADA           APP       Eduardo Pereira     Thiago Silva             8640.00
       4 09-APR-26           CANCELADA         TELEFONE  Yasmin Cardoso      Marcos Pontes           11425.50
       5 27-APR-26           ABERTA            APP       Olivia Pinto        Patricia Ramos            3150.00
```

`SELECT COUNT(*) FROM V_VENDAS_RESUMO;` → **150 linhas** (uma por venda).

Por que essa view resolve o problema operacional:

- **Um contrato em vez de cinco tabelas.** O sistema inteiro (relatórios, APEX, integrações) passa a falar `V_VENDAS_RESUMO`. O JOIN triplício (`tb_venda` + `tb_cliente` + `tb_vendedor`) fica escrito **uma única vez**. Se amanhã a modelagem mudar (ex.: vendedor virar tabela de equipe), o DBA troca a definição com `CREATE OR REPLACE VIEW` e nenhum consumidor quebra — a query deles continua igual. Isso é o "contrato de dados".
- **`OR REPLACE` não perde privilégio.** Segundo a documentação do Oracle, substituir a view preserva os `GRANT` já concedidos; dar `DROP` + `CREATE` novo derrubaria todos os grants e obrigaría a religar tudo (Oracle Database 23ai, *Managing Views*).
- **`WITH READ ONLY`.** É a cláusula que transforma a view em contrato de leitura pura: qualquer `INSERT`/`UPDATE`/`DELETE` via view falha com `ORA-42399: cannot perform a DML operation on a read-only view`. Sem ela, uma view de join ainda é *potencialmente* atualizável nas colunas de uma tabela "key-preserved" — e view de relatório aceitando UPDATE é porta de entrada para sujeira em produção.

---

## Parte 2 — Camada de Segurança e Privacidade (LGPD)

### Questão 2: View de Cliente Público (V_CLIENTE_PUBLICO)

```sql
CREATE OR REPLACE VIEW V_CLIENTE_PUBLICO AS
SELECT id_cliente,
       nome,
       email,
       dt_cadastro
FROM tb_cliente
WHERE ativo = 'S'
WITH READ ONLY;
```

A ocultação de CPF e telefone não é filtro: é **supressão de coluna** no `SELECT` da view. O dado sensível continua na tabela base (quem precisa, acessa a tabela com privilégio próprio), mas quem só tem acesso à view simplesmente não o enxerga — nem por `SELECT *`, nem por dicionário de dados da view.

Base legal e princípios da LGPD que esse desenho atende (Lei nº 13.709/2018):

- **Art. 6º, III — necessidade (minimização):** "limitação do tratamento ao mínimo necessário... dados pertinentes, proporcionais e não excessivos". Marketing faz segmentação e comunicação; para isso precisa de nome, e-mail e data de cadastro — **não** de CPF nem de telefone.
- **Art. 6º, I — finalidade:** o tratamento fica compatível com a finalidade informada (campanha), sem reuso posterior incompatível.
- **Art. 6º, VII — segurança:** a restrição é imposta no banco, camada que o usuário final não contorna — mesmo argumento da Unidade 3 sobre "validar no banco, não só no aplicativo".
- **Art. 5º, XI e Art. 12:** dado anonimizado deixa de ser dado pessoal; suprimir o identificador direto (CPF) e o contato direto (telefone) é o passo mais barato de minimização que existe — e sai de graça numa view.

Verificação prática da camada de segurança (criei o usuário `MARKETING`, dei `SELECT` **só** na view e conferi que a tabela base ficou invisível para ele):

```sql
-- como DBA
CREATE USER MARKETING IDENTIFIED BY marketing;
GRANT CREATE SESSION             TO MARKETING;
GRANT SELECT ON VENDAS.V_CLIENTE_PUBLICO TO MARKETING;
-- (tb_cliente nunca recebeu grant — e, se tivesse, seria revogado)
```

```sql
-- como MARKETING
SELECT COUNT(*) FROM VENDAS.V_CLIENTE_PUBLICO;  --> 25
SELECT cpf      FROM VENDAS.tb_cliente WHERE ROWNUM = 1;
```

```
ERROR at line 1:
ORA-00942: table or view "VENDAS"."TB_CLIENTE" does not exist
```

O Oracle responde "não existe" e não "sem permissão" justamente para não confirmar a existência do objeto (enumeration). Teste de DML também trava:

```
UPDATE V_CLIENTE_PUBLICO SET nome = 'X' WHERE id_cliente = 1;
ERROR: ORA-42399: cannot perform a DML operation on a read-only view
```

Duas observações honestas sobre o dado deste projeto:

1. No seed atual os 25 clientes têm `ativo = 'S'` (nenhum inativo), então a view devolve as 25 linhas. O `WHERE ativo = 'S'` é a regra que vale quando o cadastro tiver inativos — ele não é inútil, é pré-condição de uso futuro.
2. `SELECT *` numa view cria contrato frágil: o Oracle expande o `*` na lista de colunas na hora do `CREATE`, e colunas novas na tabela base **não** aparecem na view até recriá-la. Por isso a lista de colunas explícita acima.

**Se o marketing exigir "CPF parcial"** (ex.: confirmar identidade sem expor o documento completo), aí sim troca-se supressão por mascaramento — o dado deixa de ser o CPF verdadeiro, mas ainda identifica parcialmente:

```sql
SELECT id_cliente,
       nome,
       email,
       SUBSTR(cpf, 1, 3) || '.***.***-**'              AS cpf_mascarado,
       REGEXP_REPLACE(telefone, '\d{5}$', 'XXXXX')     AS telefone_mascarado,
       dt_cadastro
FROM tb_cliente
WHERE ativo = 'S'
WITH READ ONLY;
```

Mascaramento é mais frágil que supressão (depende de sempre usar a view, nunca a tabela) — começa por suprimir, só mascara se houver requisito real de negócio.

---

## Parte 3 — Inteligência de Negócio (Views Analíticas para BI)

### Questão 3: View de Receita por Categoria (V_VENDAS_POR_CATEGORIA)

```sql
CREATE OR REPLACE VIEW V_VENDAS_POR_CATEGORIA AS
SELECT TRUNC(v.dt_venda, 'MM') AS mes_ref,
       cat.nome                AS categoria,
       SUM(i.valor_total)      AS faturamento
FROM tb_venda_item i
JOIN tb_venda v       ON v.id_venda       = i.id_venda
JOIN tb_produto p     ON p.id_produto     = i.id_produto
JOIN tb_categoria cat ON cat.id_categoria = p.id_categoria
WHERE v.status = 'FECHADA'
GROUP BY TRUNC(v.dt_venda, 'MM'), cat.nome;

SELECT * FROM V_VENDAS_POR_CATEGORIA
 ORDER BY mes_ref DESC, faturamento DESC
 FETCH FIRST 8 ROWS ONLY;
```

Retorno do Oracle:

```
MES_REF    CATEGORIA                    FATURAMENTO
---------- ---------------------------- -----------
01-JUL-26  Eletrodomésticos                  28487.50
01-JUL-26  Móveis e Decoração                17347.50
01-JUL-26  Esporte e Lazer                     6389.25
01-JUL-26  Tecnologia e Informática            5337.00
01-JUL-26  Papelaria e Escritório               519.60
01-JUN-26  Tecnologia e Informática           25976.50
01-JUN-26  Eletrodomésticos                   24374.00
01-JUN-26  Esporte e Lazer                    13085.00
```

`SELECT COUNT(*) FROM V_VENDAS_POR_CATEGORIA;` → **35 linhas** (7 meses × 5 categorias).

Decisões de modelagem que o professor cobra:

- **Grão da análise = item de venda, não a venda.** Uma venda pode misturar categorias (notebook + cadeira), então agrupar por categoria só é possível no nível de `tb_venda_item`. Por isso a view soma `i.valor_total` e cruza `item → produto → categoria`, puxando `tb_venda` só para o filtro de status e a data.
- **Conferência de consistência:** no seed, `SUM(valor_total dos itens) = valor_liquido da venda` nas **150/150 vendas** — ou seja, a soma por categoria fecha exatamente com o faturamento da empresa, sem "vazar" desconto nem inventar centavos. Se a regra de negócio mudasse (desconto aplicado só no cabeçalho da venda), o cálculo teria que repartir `desconto_total` proporcionalmente aos itens; aqui não é o caso.
- **Filtro de status dentro da view.** `'FECHADA'` no `WHERE` do bloco de agregação: `ABERTA` e `CANCELADA` nunca entram no faturamento. Colocar isso dentro da view é o ponto da unidade — a regra analítica fica centralizada e ninguém precisa lembrar do `WHERE` em cada relatório.
- **`TRUNC(dt_venda, 'MM')`** normaliza a data para o primeiro dia do mês (`01-JUL-26`), criando a dimensão de tempo estável que o painel de BI usa para fatiar mês a mês.
- View com `GROUP BY`/agregação **não é atualizável por natureza** (restrição do próprio `CREATE VIEW`); para o BI isso é feature, não bug — mas se um dia precisarem gravar por ela, só com trigger `INSTEAD OF`.

### Questão 4: Consumindo a View Analítica

```sql
SELECT mes_ref,
       categoria,
       faturamento
FROM V_VENDAS_POR_CATEGORIA
WHERE mes_ref = TRUNC(SYSDATE, 'MM')   -- mês corrente
  AND faturamento > 5000               -- estritamente superior a R$ 5.000,00
ORDER BY faturamento DESC;
```

Pontos que a questão testa:

- **`WHERE` e não `HAVING`.** Parece contra-intuitivo (agregado normally vive no `HAVING`), mas a agregação já aconteceu **dentro** da view: na consulta externa, `V_VENDAS_POR_CATEGORIA` é uma tabela derivada com uma coluna chamada `faturamento` linha a linha. Filtrar coluna de tabela derivada é trabalho de `WHERE`. O `HAVING` só seria necessário se o `GROUP BY` estivesse no mesmo bloco de consulta — e, cuidado, `HAVING` sem `GROUP BY` no Oracle forma um grupo único com todas as linhas e devolveria no máximo uma linha, não o ranking por categoria.
- **Estritamente superior = `>`**, não `>=`. Exatamente R$ 5.000,00 ficaria de fora.
- **Mês corrente = `TRUNC(SYSDATE, 'MM')`.** `SYSDATE` traz o relógio do servidor; o `TRUNC` com `'MM'` corta para o dia 1 do mês corrente (`01-OCT-26` nesta execução), casando com o formato de `mes_ref` produzido pela view. Comparar com `BETWEEN '01/10/2026' AND '31/10/2026'` funciona, mas quebra em fevereiro/ano bissexto e depende de formato de sessão — o `TRUNC` não quebra.

Retorno do Oracle com o seed atual:

```
no rows selected
```

**Por que vazio, e isso é esperado:** o seed só tem vendas de `2026-01-01` a `2026-07-30`. O "mês corrente" do servidor é **outubro/2026**, que não tem nenhuma venda lançada. A query está correta — é o dado que não existe. Isso é bom de saber em produção: painel "mês corrente" vazio significa ou mês sem vendas ainda, ou carga atrasada, nunca erro da query.

Para provar a lógica com dados reais, mesma consulta fixando o último mês do seed (julho/2026):

```sql
SELECT mes_ref, categoria, faturamento
FROM V_VENDAS_POR_CATEGORIA
WHERE mes_ref = TO_DATE('2026-07-01', 'YYYY-MM-DD')
  AND faturamento > 5000
ORDER BY faturamento DESC;
```

```
MES_REF    CATEGORIA                    FATURAMENTO
---------- ---------------------------- -----------
01-JUL-26  Eletrodomésticos                  28487.50
01-JUL-26  Móveis e Decoração                17347.50
01-JUL-26  Esporte e Lazer                     6389.25
01-JUL-26  Tecnologia e Informática            5337.00
```

`Papelaria e Escritório` ficou de fora com R$ 519,60 — confirma que o filtro de valor corta de verdade.

---

## Referências consultadas

- Oracle Database 23ai — *SQL Language Reference*, `CREATE VIEW` (`WITH READ ONLY`, `WITH CHECK OPTION`, restrições de DML em views de join e agregação): <https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-VIEW.html>
- Oracle Database 23ai — *Administrator's Guide*, *Managing Views, Sequences, and Synonyms* (privilegios do dono da view, `OR REPLACE` preservando grants, `ORA-42399`): <https://docs.oracle.com/en/database/oracle/oracle-database/23/admin/managing-views-sequences-and-synonyms.html>
- Lei nº 13.709/2018 (LGPD) — Art. 5º (anonimização), Art. 6º (finalidade, necessidade/minimização, segurança), Art. 12 (dados anonimizados): <https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm>
- ANPD — *Estudo técnico sobre a anonimização de dados na LGPD*: <https://www.gov.br/anpd/pt-br/centrais-de-conteudo/documentos-tecnicos-orientativos/>
