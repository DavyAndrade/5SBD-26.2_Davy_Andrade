# 5SBD — Unidade 7: Sequences no Oracle Database

Uma **Sequence** é um objeto de banco de dados compartilhado, independente de tabelas específicas, projetado para gerar valores inteiros sequenciais únicos de forma atômica e com altíssima concorrência. É utilizada primordialmente na geração de chaves primárias numéricas sintéticas (surrogate keys).

---

## 1. Fundamentos Teóricos

### Definição e Propósito

- **Independência de Transação**: a geração de valores por uma sequence é completamente dissociada da transação corrente. Quando uma sessão solicita um valor, a alocação ocorre instantaneamente e **não é revertida por um `ROLLBACK`**. Caso a transação seja cancelada, o número consumido é permanentemente perdido. Essa arquitetura garante alta performance ao evitar bloqueios (locks) entre sessões simultâneas que estejam inserindo dados na mesma tabela.

### Pseudocolunas Fundamentais

| Pseudocoluna | Descrição |
|---|---|
| `NEXTVAL` | Incrementa a sequência e retorna o próximo valor disponível. Deve obrigatoriamente ser executado ao menos uma vez na sessão antes que a pseudocoluna `CURRVAL` possa ser consultada. |
| `CURRVAL` | Retorna o valor atual da sequência alocado para a sessão corrente (sem incrementar). Não pode ser utilizado em uma sessão sem antes ter inicializado o `NEXTVAL`. |

### Parâmetros de Configuração

| Parâmetro | Descrição |
|---|---|
| `START WITH` | Define o valor inicial do gerador. |
| `INCREMENT BY` | Especifica o passo de incremento (positivo para sequências crescentes, negativo para decrescentes). |
| `MINVALUE` / `MAXVALUE` | Estabelecem os limites inferior e superior. Podem ser substituídos por `NOMINVALUE` ou `NOMAXVALUE`. |
| `CYCLE` vs `NOCYCLE` | Define se a sequência reinicia automaticamente ao atingir o limite estipulado (`CYCLE`) ou lança o erro `ORA-08004` ao exceder a capacidade (`NOCYCLE`). |
| `CACHE` vs `NOCACHE` | Quantidade de números mantidos na memória compartilhada (SGA - Shared Global Area) para acesso em microssegundos sem requerer I/O no dicionário de dados. Em eventual crash da instância, os valores em memória não utilizados são perdidos, gerando lacunas (gaps). A opção `NOCACHE` evita perdas, porém gera contenção severa (row cache lock). |
| `ORDER` vs `NOORDER` | Garante a alocação de números rigorosamente em ordem de solicitação em ambientes Oracle RAC (com alto custo de rede inter-nós) vs alocação livre concorrente (`NOORDER`). |

### Evolução Sintática no Oracle

| Abordagem | Descrição |
|---|---|
| **Legada (Pré-12c)** | Atribuição manual na instrução `INSERT` ou automatização via Triggers `BEFORE INSERT`. |
| **Moderna (Oracle 12c+)** | Atribuição direta na cláusula `DEFAULT` da definição da coluna (`DEFAULT seq_nome.NEXTVAL`). |
| **Colunas Identity (Oracle 12c+)** | Uso da sintaxe `GENERATED AS IDENTITY`, que cria e gerencia uma sequence implícita sob o capô. |

---

## 2. Roteiro Prático: Laboratório no Oracle APEX

### Etapa 1: Criação e Exploração Básica de Sequences

```sql
-- 1. Criação de uma Sequence com CACHE e controle de limites
CREATE SEQUENCE seq_clientes_id
    START WITH 1000
    INCREMENT BY 1
    MINVALUE 1000
    MAXVALUE 999999
    CACHE 20
    NOCYCLE;

-- 2. Consumo e avanço de valores com NEXTVAL
SELECT seq_clientes_id.NEXTVAL AS proximo_id FROM DUAL;

-- 3. Consulta ao valor corrente alocado na sessão com CURRVAL
SELECT seq_clientes_id.CURRVAL AS id_atual FROM DUAL;

-- 4. Novo avanço para observar a progressão
SELECT seq_clientes_id.NEXTVAL AS novo_id FROM DUAL;
```

### Etapa 2: Integração de Sequences com Tabelas Relacionais

```sql
-- 1. Criação da tabela de clientes usando DEFAULT Sequence
CREATE TABLE tb_clientes_apex (
    id_cliente      NUMBER DEFAULT seq_clientes_id.NEXTVAL PRIMARY KEY,
    nome_razao      VARCHAR2(100) NOT NULL,
    cpf_cnpj        VARCHAR2(18) NOT NULL,
    cidade          VARCHAR2(50) NOT NULL,
    data_cadastro   DATE DEFAULT SYSDATE NOT NULL
);

-- 2. Inserção sem especificar a coluna de Chave Primária
INSERT INTO tb_clientes_apex (nome_razao, cpf_cnpj, cidade)
VALUES ('Alpha Consultoria e Tecnologia', '12.345.678/0001-90', 'Rio de Janeiro');

INSERT INTO tb_clientes_apex (nome_razao, cpf_cnpj, cidade)
VALUES ('Beta Soluções Logísticas', '98.765.432/0001-11', 'Niterói');

COMMIT;

-- 3. Verificação dos IDs atribuídos pela Sequence
SELECT id_cliente, nome_razao, cidade, data_cadastro
FROM tb_clientes_apex
ORDER BY id_cliente;
```

### Etapa 3: Demonstração Prática de Gaps (Lacunas) por Rollback

```sql
-- 1. Inserir uma transação de teste
INSERT INTO tb_clientes_apex (nome_razao, cpf_cnpj, cidade)
VALUES ('Gama Engenharia e Projetos', '45.123.789/0001-55', 'São Paulo');

-- 2. Cancelar a transação
ROLLBACK;

-- 3. Inserir um novo registro e comitar
INSERT INTO tb_clientes_apex (nome_razao, cpf_cnpj, cidade)
VALUES ('Delta Distribuidora de Peças', '33.222.111/0001-44', 'Curitiba');

COMMIT;

-- 4. Consultar e constatar a lacuna intencional no id_cliente
SELECT id_cliente, nome_razao FROM tb_clientes_apex ORDER BY id_cliente;
```

> **Nota Didática**: O valor consumido durante a instrução `INSERT` revertida não é reutilizado. Isso garante que sessões paralelas não fiquem bloqueadas aguardando a decisão de `COMMIT` ou `ROLLBACK` de outras transações.

### Etapa 4: Relacionamento Mestre-Detalhe Usando CURRVAL

```sql
-- 1. Tabela de Pedidos vinculada ao cliente
CREATE TABLE tb_pedidos_apex (
    id_pedido   NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    id_cliente  NUMBER NOT NULL,
    data_pedido DATE DEFAULT SYSDATE,
    valor_total NUMBER(10,2) NOT NULL,
    CONSTRAINT fk_ped_cli FOREIGN KEY (id_cliente) REFERENCES tb_clientes_apex(id_cliente)
);

-- 2. Bloco PL/SQL inserindo Cliente e Pedidos
DECLARE
    v_id_cliente NUMBER;
BEGIN
    -- Inserir novo cliente (avança a Sequence com NEXTVAL)
    INSERT INTO tb_clientes_apex (id_cliente, nome_razao, cpf_cnpj, cidade)
    VALUES (seq_clientes_id.NEXTVAL, 'Mega Atacado do Brasil', '77.888.999/0001-22', 'Belo Horizonte')
    RETURNING id_cliente INTO v_id_cliente;

    -- Inserir pedidos usando o id capturado e a pseudocoluna CURRVAL
    INSERT INTO tb_pedidos_apex (id_cliente, valor_total)
    VALUES (seq_clientes_id.CURRVAL, 4500.00);

    INSERT INTO tb_pedidos_apex (id_cliente, valor_total)
    VALUES (v_id_cliente, 12500.00);

    COMMIT;
END;
/

-- 3. Validação do relacionamento Mestre-Detalhe
SELECT c.id_cliente, c.nome_razao, p.id_pedido, p.valor_total
FROM tb_clientes_apex c
JOIN tb_pedidos_apex p ON c.id_cliente = p.id_cliente
WHERE c.nome_razao = 'Mega Atacado do Brasil';
```

### Etapa 5: Alteração de Sequences e Consulta ao Dicionário de Dados

```sql
-- 1. Aumentar o CACHE para 50 e ajustar o MAXVALUE
ALTER SEQUENCE seq_clientes_id
    CACHE 50
    MAXVALUE 2000000;

-- 2. Consultar os metadados da sequence no catálogo do Oracle
SELECT sequence_name, min_value, max_value, increment_by, cycle_flag, cache_size, last_number
FROM user_sequences
WHERE sequence_name = 'SEQ_CLIENTES_ID';
```

---

## 3. Exercícios Práticos de Fixação

### Exercício 1: Sequence com Reinício (CYCLE)

Crie uma sequência chamada `seq_ticket_diario` com `START WITH 1`, `INCREMENT BY 1`, `MINVALUE 1`, `MAXVALUE 5`, `CYCLE` e `CACHE 2`. Execute chamadas sucessivas a `NEXTVAL` e documente o comportamento do sistema ao ultrapassar o valor 5.

```sql
CREATE SEQUENCE seq_ticket_diario
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 5
    CYCLE
    CACHE 2;
```

Comportamento esperado nas chamadas a `NEXTVAL`: 1, 2, 3, 4, 5 e depois **volta para 1** em vez de dar `ORA-08004`. É o `CYCLE` fazendo o papel dele — bom para numeração de senha/ticket do dia, péssimo para PK (repetiria chave).

### Exercício 2: Migração Trigger vs DEFAULT

Escreva um código demonstrando a atribuição clássica de uma sequência via Trigger `BEFORE INSERT` (padrão pré-Oracle 12c) e compare-o com a sintaxe moderna `DEFAULT seq.NEXTVAL`. Destaque as melhorias em termos de legibilidade, manutenção e performance de execução.

```sql
-- Abordagem Legada (Trigger)
CREATE TABLE tb_legado (
    id NUMBER PRIMARY KEY,
    nome VARCHAR2(100)
);

CREATE SEQUENCE seq_legado START WITH 1 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER trg_legado_bi
BEFORE INSERT ON tb_legado
FOR EACH ROW
BEGIN
    SELECT seq_legado.NEXTVAL INTO :NEW.id FROM DUAL;
END;
/

-- Abordagem Moderna (DEFAULT + Sequence)
CREATE SEQUENCE seq_moderno START WITH 1 INCREMENT BY 1;

CREATE TABLE tb_moderno (
    id NUMBER DEFAULT seq_moderno.NEXTVAL PRIMARY KEY,
    nome VARCHAR2(100)
);
```

**Pontos de comparação**:
- **Legibilidade**: o `DEFAULT` está na definição da coluna; o trigger fica escondido em objeto separado.
- **Manutenção**: mudar a sequence no `DEFAULT` é um `ALTER TABLE`; no trigger exige `DROP/CREATE` do trigger.
- **Performance**: o `DEFAULT` evita a troca de contexto SQL → PL/SQL que o trigger força a cada linha.

### Exercício 3: Análise de Concorrência e CACHE

Explique os impactos arquiteturais da opção `NOCACHE` em um sistema de alta concorrência (OLTP), abordando a contenção na área de memória compartilhada (row cache lock na SGA) e os gargalos de I/O na atualização do dicionário de dados.

> **Resposta esperada**: Com `NOCACHE`, cada chamada a `NEXTVAL` força o Oracle a gravar no dicionário de dados (tabela `SEQ$`) e manter o latch/row cache lock da sequência. Em alta concorrência, isso serializa as sessões — cada uma espera a outra liberar o lock na sequence. O I/O de dicionário vira gargalo e a throughput cai drasticamente. Com `CACHE N` (ex.: 20, 100, 1000), o Oracle aloca um lote de `N` números na SGA; cada sessão consome do lote sem tocar no dicionário até esgotar. O trade-off: em crash, os números do lote não usados são perdidos (gaps), mas a concorrência escala linearmente.

---

## 4. Checklist de Boas Práticas e Arquitetura

| Prática | Recomendação | Justificativa |
|---|---|---|
| **Uso de CACHE** | Requisito recomendado | Utilize no mínimo `CACHE 20` (padrão). Em ambientes de alto volume transacional, dimensione para valores entre 100 e 1000 para minimizar latência na memória. |
| **Opção CYCLE** | Evite em Chaves Primárias | O ciclo reutiliza valores antigos, o que gera violação de restrição de unicidade (`ORA-00001: unique constraint violated`). |
| **Tratamento de Gaps** | Aceite por arquitetura | Sequences garantem exclusividade e alta performance, mas não garantem sequencialidade rígida sem lacunas. |
| **Numeração Fiscal** | Não utilize Sequences | Para regras de negócios com exigência legal de ausência de lacunas (ex: notas fiscais), utilize tabelas de controle com bloqueio pessimista (`SELECT FOR UPDATE`). |

---

## Referências

- Oracle Database SQL Language Reference — `CREATE SEQUENCE`, `ALTER SEQUENCE`
- Oracle Database Concepts — *Sequences, Identity Columns*
- Oracle Database Administrator's Guide — *Managing Sequences*

---

**Dica para Google Docs**: Copie este markdown e use o plugin "Markdown to Docs" ou a função "Importar arquivo Markdown" do Google Docs. As tabelas e blocos de código se manterão formatados. Para versão PDF, use `File > Download > PDF Document` após a importação.