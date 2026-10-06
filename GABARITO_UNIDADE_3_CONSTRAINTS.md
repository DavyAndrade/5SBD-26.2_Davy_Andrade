# 5SBD — Unidade 3: Modelagem Física e Qualidade de Dados (Constraints)

Respostas comentadas das questões sobre restrições físicas no Oracle Database 23ai (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK).

## Parte 1 — Testando a Resiliência (Princípio de "Falhar Cedo")

### Questão 1: Violação de Chave Estrangeira (FK)

```sql
INSERT INTO tb_venda (id_cliente, id_vendedor, dt_venda, status, canal)
VALUES (9999, 1, SYSDATE, 'ABERTA', 'LOJA');
```

Retorno do Oracle: `ORA-02291: integrity constraint (FK_TB_VENDA_CLIENTE) violated - parent key not found`

Cliente 9999 nunca foi cadastrado, então o Oracle nem deixa a venda nascer. A `fk_tb_venda_cliente` existe justamente pra evitar "venda órfã": aquela venda que aparece no relatório mas ninguém sabe de quem é. Se o cliente não está na tabela, a venda não entra — e é isso que mantém o CRM e as métricas comerciais confiáveis.

### Questão 2: Violação de Domínio (CHECK Constraint)

```sql
UPDATE tb_venda
SET status = 'PENDENTE'
WHERE id_venda = 1;
```

Retorno do Oracle: `ORA-02290: check constraint (CK_TB_VENDA_STATUS) violated`

O `ck_tb_venda_status` só aceita `ABERTA`, `FECHADA` ou `CANCELADA`. A validação mora no banco, não na interface, de propósito: se um bug, um script improvisado ou uma integração externa tentar forçar outro valor, o banco barra na hora. No aplicativo o dado sujo ainda escaparia por um pulo no front-end; no banco ele simplesmente não entra.

### Questão 3: Impedindo Preços Absurdos

```sql
INSERT INTO tb_produto (id_categoria, sku, nome, preco_unit)
VALUES (1, 'SKU-TEMP-01', 'Produto Teste Negativo', -15.00);
```

Retorno do Oracle: `ORA-02290: check constraint (CK_TB_PRODUTO_PRECO) violated`

O `ck_tb_produto_preco` (`preco_unit > 0`) derruba a inserção. Cobre dois cenários comuns: o erro de digitação (sinal trocado, vírgula no lugar errado) e o malandro que tenta lançar preço negativo pra "ganhar" no inventário. Um produto a -15.00 viraria crédito fantasma nos dashboards de receita.

## Parte 2 — Evoluindo a Modelagem Física (DDL)

### Questão 4: Limite de Desconto de Itens (CHECK)

```sql
ALTER TABLE tb_venda_item
ADD CONSTRAINT ck_tb_item_desconto_max
CHECK (desconto_item <= (preco_unit * 0.50));
```

No Oracle o CHECK compara colunas da mesma linha sem enroscos — e é exatamente o que a regra pede: desconto contra o preço unitário daquele item. Detalhe que o professor cobra: **CHECK não aceita subquery**, não dá pra consultar `tb_produto` de dentro dele. Usar o `preco_unit` da linha tem lado bom: é o preço congelado na venda, que é o que interessa na hora de conceder o desconto.

### Questão 5: Garantia de Unicidade de Contato (UNIQUE)

```sql
ALTER TABLE tb_cliente
ADD CONSTRAINT uq_tb_cliente_telefone UNIQUE (telefone);
```

O UNIQUE gera um índice exclusivo por baixo e não deixa o telefone repetir. A pegadinha: **`NULL` escapa da unicidade** — vários clientes podem ficar sem telefone, mas se preencherem, tem que ser único. E se já existirem duplicatas na base, o `ALTER` falha; limpe antes:

```sql
SELECT telefone, COUNT(*) FROM tb_cliente
 WHERE telefone IS NOT NULL
 GROUP BY telefone HAVING COUNT(*) > 1;
```

## Parte 3 — Comportamento de Exclusão (CASCADE vs. Soft Delete)

### Questão 6: Exclusão em Cascata (ON DELETE CASCADE)

```sql
DELETE FROM tb_venda WHERE id_venda = 1;

-- Conferindo que os filhos foram limpos automaticamente:
SELECT * FROM tb_venda_item WHERE id_venda = 1;
```

A `fk_item_venda` foi criada com `ON DELETE CASCADE`, então ao apagar a venda pai o Oracle percorre `tb_venda_item` e apaga tudo que aponta pra ela — automático e sem erro. Que é também o lado perigoso: um `DELETE` sem `WHERE` levaria venda e itens junto num piscar de olhos. Protege contra dado inconsistente, mas exige transação e um backup por perto.

### Questão 7: Exclusão Lógica (Soft Delete)

```sql
UPDATE tb_vendedor
SET ativo = 'N'
WHERE id_vendedor = 1;
```

Apagar um vendedor (ou cliente, ou produto) com histórico de faturamento é pedir problema: as vendas dele referenciam a PK por FK — ou o `DELETE` falha, ou leva o histórico junto. O soft delete inativa o cadastro pra novos lançamentos (o `ck_tb_vendedor_ativo` garante que só `'S'`/`'N'` circule) e mantém o histórico inteiro em pé. No fim é a pergunta de sempre: apagar de verdade ou só parar de usar? Aqui, só para de usar.
