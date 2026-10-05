# 5SBD — Unidade 3: Modelagem Física e Qualidade de Dados (Constraints)

Restrições físicas no Oracle Database 23ai (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK) como guardiãs da qualidade e integridade dos dados operacionais.

## Parte 1 — Testando a Resiliência (Princípio de "Falhar Cedo")

### Questão 1: Violação de Chave Estrangeira (FK)
Escreva um `INSERT` que tente registrar uma venda amarrada a um ID de cliente inexistente (ex: `9999`). Execute e analise qual constraint impediu o registro e qual regra comercial ela garante.

### Questão 2: Violação de Domínio (CHECK Constraint)
Escreva um `UPDATE` que tente alterar o status de uma venda para o valor inválido `"PENDENTE"`. Analise o erro retornado e por que essa validação deve residir no banco e não apenas no aplicativo.

### Questão 3: Impedindo Preços Absurdos
Insira um novo produto em `tb_produto` com preço unitário negativo (ex: `-15.00`). Identifique qual constraint do modelo físico foi acionada para blindar o sistema.

## Parte 2 — Evoluindo a Modelagem Física (DDL)

### Questão 4: Limite de Desconto de Itens (CHECK)
`ALTER TABLE` para adicionar `CHECK` em `tb_venda_item` garantindo que nenhum desconto unitário (`desconto_item`) ultrapasse 50% do preço unitário do respectivo produto.

### Questão 5: Garantia de Unicidade de Contato (UNIQUE)
DDL para adicionar `UNIQUE` na coluna `telefone` de `tb_cliente`, impedindo que dois clientes compartilhem o mesmo canal de contato no CRM.

## Parte 3 — Comportamento de Exclusão (CASCADE vs. Soft Delete)

### Questão 6: Exclusão em Cascata (ON DELETE CASCADE)
Delete um registro pai em `tb_venda` com filhos em `tb_venda_item`. Analise o comportamento automático do banco e discuta o perigo do uso indiscriminado da cláusula.

### Questão 7: Exclusão Lógica (Soft Delete)
SQL para desativar logicamente um vendedor desligado (coluna `ativo` = `"N"`). Justifique por que a exclusão lógica é preferível ao `DELETE` físico em bancos corporativos com histórico de faturamento.
