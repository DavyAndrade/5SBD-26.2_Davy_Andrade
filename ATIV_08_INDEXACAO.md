# 5SBD — Unidade 6: Indexação no Oracle Database

Indexação é a estrutura secundária que minimiza operações de E/S ao localizar registros. No Oracle, a recuperação de dados ocorre via dois mecanismos: **Full Table Scan (FTS)** — lê todos os blocos abaixo da High Water Mark (HWM), eficiente para leitura sequencial maciça, ineficiente para consultas pontuais; e **Acesso via Índice** — o otizador consulta a estrutura do índice para obter o ROWID direto e realiza a leitura do bloco específico. O ROWID é o endereço físico interno (18 caracteres base-64: `OOOOOOFFFBBBPPPPRR`), com 4 componentes: Data Object ID (6 chars), Datafile ID (3 chars), Block Number (6 chars), Row Number (3 chars). Quando o operador `TABLE ACCESS BY USER ROWID` ou `TABLE ACCESS BY INDEX ROWID` é usado, o Oracle acessa diretamente a posição em tempo constante O(1).

---

## 1. Fundamentos Teóricos

### Anatomia do ROWID

| Componente | Tamanho | Descrição |
|---|---|---|
| Data Object ID | 6 caracteres | Identifica o objeto no dicionário de dados do Oracle. |
| Datafile ID | 3 caracteres | Identifica o arquivo de dados (datafile) relativo à tablespace. |
| Block Number | 6 caracteres | Identifica o bloco de dados exato contendo a linha. |
| Row Number | 3 caracteres | Identifica o número do slot (posição) da linha dentro do bloco. |

### Principais Tipos de Índices

#### B-Tree (Balanced Tree)

Estrutura padrão do Oracle. Mantém-se balanceada automaticamente: a distância da raiz até qualquer bloco folha (leaf block) é idêntica.

- **Arquitetura**: Bloco raiz (root), blocos de ramo (branch) e blocos folha (leaf). Os blocos folha contêm a chave do índice e o respectivo ROWID, encadeados em lista duplamente ligada (permite varreduras ascendentes e descendentes).
- **Complexidade de busca**: O(log N), onde N é o número de blocos no índice.
- **Recomendação**: Ideal para colunas com alta cardinalidade (muitos valores distintos), como CPF, matrícula ou IDs primários em sistemas OLTP.

#### Function-Based Index (FBI)

O otimizador ignora índices B-Tree comuns quando a coluna indexada é envolvida por uma função determinística na cláusula WHERE (ex: `WHERE UPPER(nome) = 'ALICE'`).

- O FBI pré-calcula o resultado da função/expressão e armazena os valores pré-computados com seus ROWIDs na estrutura da árvore B-Tree.
- Permite otimizar cláusulas contendo `UPPER`, `LOWER`, `TRUNC`, `ROUND` ou expressões matemáticas.
- Exemplos de uso: `CREATE INDEX idx_func_nome_upper ON tb_funcionarios(UPPER(nome));`

#### Índice Composto (Composite Index)

Índice criado sobre duas ou mais colunas de uma mesma tabela (limite de até 32 colunas).

- **Regra da Leading Column (coluna líder)**: O índice B-Tree composto é organizado primordialmente pela primeira coluna declarada. Consultas que não utilizam a coluna líder na cláusula WHERE tendem a ignorar o índice ou demandar operações mais dispendiosas de varredura completa do índice (Index Fast Full Scan / Index Skip Scan).
- **Index-Only Scan (Index Fast Full Scan)**: Ocorre quando a instrução SELECT requisita apenas colunas presentes na própria estrutura do índice. O Oracle satisfaz a consulta inteira acessando apenas os blocos do índice, eliminando a fase de acesso aos blocos da tabela (`TABLE ACCESS BY INDEX ROWID`).

#### Bitmap Index

Substitui a lista de ROWID por representações compactas em vetor de bits (bitmaps).

- **Conceito**: Para cada valor distinto da coluna, cria-se uma chave contendo um bit (0 ou 1) para cada linha da tabela.
- **Recomendação**: Estrutura voltada para cenários de baixa cardinalidade (ex: Gênero, Status, Estado Civil) em ambientes de apoio à decisão (Data Warehouse / OLAP).
- **Restrição Crítica**: Operações de escrita (INSERT, UPDATE, DELETE) bloqueiam a chave inteira do bitmap, invalidando a concorrência e gerando travamentos (deadlocks ou enqueue waits) severos em ambientes OLTP de alta frequência transacional.

#### Index-Organized Tables (IOT)

Diferente de uma Heap Table (dados inseridos em qualquer bloco livre sem ordem garantida), a IOT armazena a tabela inteira e seus dados diretamente dentro de uma estrutura B-Tree, ordenada pela chave primária.

- Reduz o espaço alocado e elimina a duplicação de ROWID + Chave.

### Custos, Manutenção e Boas Práticas

#### Overhead em Operações DML

Toda escrita (INSERT, UPDATE, DELETE) em uma tabela com múltiplos índices exige a atualização simultânea de cada estrutura de índice associada, aumentando o tempo total de transação e o volume de REDO/UNDO gerado.

#### Divisão de Blocos Folha (Leaf Block Split)

Quando um bloco folha atinge a capacidade máxima e um novo registro precisa ser indexado naquela posição, o Oracle divide o bloco folha em dois (Split 50-50 ou Split 90-10 para inserções sequenciais). Esse evento consome recurso computacional e pode levar à fragmentação do índice.

#### Manutenção do Dicionário de Dados

Acompanhar o estado e o uso das estruturas de indexação é feito via visões como `USER_INDEXES` e `USER_IND_COLUMNS`.

---

## 2. Roteiro Prático: Laboratório de Indexação no Oracle APEX

### Etapa 1: Criação da Tabela Transacional e Carga em Lote

```sql
-- 1. Criação da tabela sem índices secundários
CREATE TABLE tb_funcionarios (
    id_funcionario  NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    matricula       VARCHAR2(20) NOT NULL,
    nome            VARCHAR2(100) NOT NULL,
    email           VARCHAR2(100) NOT NULL,
    departamento    VARCHAR2(50) NOT NULL,
    cargo           VARCHAR2(50) NOT NULL,
    salario         NUMBER(10,2) NOT NULL,
    data_admissao   DATE DEFAULT SYSDATE NOT NULL,
    status          VARCHAR2(15) DEFAULT 'ATIVO' NOT NULL
);

-- 2. Carga volumosa de dados sintéticos (10.000 registros)
INSERT INTO tb_funcionarios (matricula, nome, email, departamento, cargo, salario, data_admissao, status)
SELECT 
    'MAT-' || LPAD(LEVEL, 6, '0'),
    'Funcionario ' || LEVEL,
    'user' || LEVEL || '@empresa.com.br',
    CASE MOD(LEVEL, 5)
        WHEN 0 THEN 'TI'
        WHEN 1 THEN 'RH'
        WHEN 2 THEN 'FINANCEIRO'
        WHEN 3 THEN 'VENDAS'
        ELSE 'OPERACAO'
    END,
    CASE MOD(LEVEL, 4)
        WHEN 0 THEN 'ANALISTA'
        WHEN 1 THEN 'COORDENADOR'
        WHEN 2 THEN 'GERENTE'
        ELSE 'ASSISTENTE'
    END,
    ROUND(DBMS_RANDOM.VALUE(2500, 18000), 2),
    SYSDATE - DBMS_RANDOM.VALUE(30, 3650),
    CASE WHEN MOD(LEVEL, 10) = 0 THEN 'INATIVO' ELSE 'ATIVO' END
FROM DUAL
CONNECT BY LEVEL <= 10000;

COMMIT;
```

### Etapa 2: Análise da Consulta sem Índice (Full Table Scan)

```sql
SELECT id_funcionario, nome, departamento, salario
FROM tb_funcionarios
WHERE matricula = 'MAT-005420';
```

**Observação didática no Explain Plan**: O otizador gera um plano com o operador `TABLE ACCESS FULL`. O Oracle lê sequencialmente todos os blocos de dados alocados para a tabela `TB_FUNCIONARIOS` a fim de encontrar uma única correspondência, resultando em maior custo de E/S.

### Etapa 3: Aplicação de Índice B-Tree Único e Comparação de Custo

```sql
-- Criação do índice B-Tree Único
CREATE UNIQUE INDEX idx_func_matricula ON tb_funcionarios(matricula);

-- Reexecutar a consulta com Explain Plan
SELECT id_funcionario, nome, departamento, salario
FROM tb_funcionarios
WHERE matricula = 'MAT-005420';
```

**Observação didática no Explain Plan**: O plano de execução muda para `INDEX UNIQUE SCAN` apontando para `IDX_FUNC_MATRICULA`, seguido da operação `TABLE ACCESS BY INDEX ROWID BATCHED`. O custo de busca cai bruscamente — tipicamente de dezenas/centenas de blocos para apenas 2 ou 3 leituras.

### Etapa 4: O Desafio do Function-Based Index (FBI)

```sql
-- 1. Consulta aplicando função UPPER no nome (gera TABLE ACCESS FULL mesmo se houver índice comum no nome)
SELECT matricula, nome, cargo, salario
FROM tb_funcionarios
WHERE UPPER(nome) = 'FUNCIONARIO 2500';

-- 2. Criação do Function-Based Index
CREATE INDEX idx_func_nome_upper ON tb_funcionarios(UPPER(nome));

-- 3. Reavaliar com Explain Plan
SELECT matricula, nome, cargo, salario
FROM tb_funcionarios
WHERE UPPER(nome) = 'FUNCIONARIO 2500';
```

**Observação didática no Explain Plan**: A primeira consulta resulta em `TABLE ACCESS FULL` porque a função `UPPER` transforma o valor da coluna em tempo de execução, impedindo a comparação direta com a chave do índice B-Tree normal. Após a criação do índice funcional `idx_func_nome_upper`, o otizador utiliza a operação `INDEX RANGE SCAN`.

### Etapa 5: Índice Composto e a Otimização de Cobertura (Index-Only Scan)

```sql
-- 1. Criação de índice composto (departamento + cargo + salario)
CREATE INDEX idx_func_dep_cargo_sal ON tb_funcionarios(departamento, cargo, salario);

-- 2. Consulta filtrando pela coluna líder (departamento) e retornando apenas colunas do próprio índice
SELECT cargo, salario
FROM tb_funcionarios
WHERE departamento = 'TI' AND cargo = 'ANALISTA';
```

**Observação didática no Explain Plan**: Observe a ocorrência da operação `INDEX RANGE SCAN` **sem** a necessidade do nó posterior `TABLE ACCESS BY INDEX ROWID`. Como as colunas requisitadas na cláusula SELECT (`cargo`, `salario`) e nas cláusulas de filtro WHERE (`departamento`, `cargo`) pertencem todas ao índice, o Oracle encerra a busca no próprio bloco folha do índice (`Index-Only Scan`).

### Etapa 6: Consulta ao Dicionário de Dados

```sql
-- Listar os índices criados pelo usuário e seu status
SELECT index_name, index_type, uniqueness, status
FROM user_indexes
WHERE table_name = 'TB_FUNCIONARIOS';

-- Detalhar as colunas e posições em índices compostos
SELECT index_name, column_name, column_position
FROM user_ind_columns
WHERE table_name = 'TB_FUNCIONARIOS'
ORDER BY index_name, column_position;
```

---

## 3. Exercícios Práticos de Avaliação para os Alunos

### Exercício 1 (Seletividade e Leading Column)

**Enunciado**: Execute a consulta abaixo no Oracle APEX e inspecione o plano de execução gerado via botão Explain Plan:

```sql
SELECT nome, salario
FROM tb_funcionarios
WHERE cargo = 'ANALISTA';
```

**Pergunta**: Explique detalhadamente por que o índice composto `idx_func_dep_cargo_sal` (criado na Etapa 5) não gerou um `INDEX RANGE SCAN` direto e eficiente nesta instrução, e como a regra da Leading Column (coluna líder) fundamenta esse comportamento do otimizador Oracle.

---

### Exercício 2 (Indexação Temporal)

**Enunciado**: Suponha uma demanda em que o relatório de auditoria fiscal realiza consultas frequentes buscando funcionários admitidos em um determinado ano, utilizando a sintaxe:

```sql
SELECT * 
FROM tb_funcionarios 
WHERE EXTRACT(YEAR FROM data_admissao) = 2022;
```

**Tarefa**: Escreva a instrução SQL completa DDL para criar um Function-Based Index apropriado para essa consulta e apresente a sintaxe SQL de validação utilizando o Dicionário de Dados do Oracle (`USER_INDEXES`).

---

### Exercício 3 (Análise Crítica de Trade-offs)

**Enunciado**: Um desenvolvedor júnior propôs a criação de índices individuais para todas as colunas da tabela `tb_funcionarios` com o objetivo de "garantir que nenhuma consulta do sistema fique lenta".

**Tarefa**: Elabore uma justificativa técnica (mínimo de 2 parágrafos) desconstruindo essa abordagem para a equipe de arquitetura. Aborde os impactos físicos e de infraestrutura nos seguintes tópicos:

- **Desempenho e overhead em operações transacionais de escrita (INSERT, UPDATE, DELETE)**: cada INSERT/UPDATE/DELETE deve atualizar todos os índices criados, aumentando o tempo de transação e o volume de REDO/UNDO.
- **Consumo de espaço em disco e comportamento do Buffer Cache em memória**: índices ocupam espaço na tablespace e nas páginas do Buffer Cache; muitos índices podem provocar evicção de dados úteis da memória, piorando o desempenho geral.
- **Decisões do Otimizador Baseado em Custo (CBO - Cost-Based Optimizer)**: o CBO avalia o custo de usar cada índice; com muitos índices, o tempo de otimização cresce e o plano escolhido pode não ser o mais eficiente para a carga de trabalho real.

---

## 4. Checklist de Boas Práticas

| Tema | Recomendação |
|---|---|
| **Seleção de colunas para indexar** | Priorize alta cardinalidade (CPF, IDs) em OLTP; baixa cardinalidade (status, gênero) só em Data Warehouse com Bitmap Index. |
| **Índice composto** | Coloque a coluna mais seletiva (filtro mais restritivo) como primeira (coluna líder). Teste `WHERE` com e sem a leading column. |
| **Function-Based Index** | Use quando a query aplicar função determinística (UPPER, LOWER, TRUNC, ROUND) sobre a coluna indexada. Evite em ambientes com alta taxa de UPDATE/DELETE na expressão indexada. |
| **Evitar excesso de índices** | Cada índice adiciona overhead em DML e consumo de space. Use `SQL Tuning Advisor` ou `V$SQL_PLAN` para validar quais realmente são usados. |
| **Manutenção** | Monitore fragmentation com `ANALYZE INDEX VALIDATE STRUCTURE` ou `DBMS_STATS`. Realize `COALESCE` ou `SPLIT` quando leaf blocks estiverem muito fragmentados. |
| **IOT (Index-Organized Table)** | Considere quando a tabela for acessada predominantemente por PK e a redução de espaço for crítica; evite em ambientes com alta concorrência de escrita. |

---

## Referências

- Oracle Database VLDB and Partitioning Guide — *Indexes*
- Oracle Database SQL Language Reference — `CREATE INDEX`, `CREATE MATERIALIZED VIEW`
- Oracle Database Concepts — *ROWID, B-Tree indexes*
- Lei nº 13.709/2018 (LGPD) — princípios de segurança e minimização no tratamento de dados
