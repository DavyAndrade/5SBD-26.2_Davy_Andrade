-- ====================================================================
-- GABARITO COMENTADO — UNIDADE 3: MODELAGEM FÍSICA E QUALIDADE DE DADOS
-- Disciplina: 5SBD - Programação de Scripts de Banco de Dados (Oracle 23ai)
-- ====================================================================

-- ---------------------------------------------------------------------
-- PARTE 1: TESTANDO A RESILIÊNCIA (falhar cedo)
-- ---------------------------------------------------------------------

-- Questão 1: Violação de Chave Estrangeira (FK)
-- Cliente 9999 nunca foi cadastrado, então o Oracle nem deixa a venda nascer.
-- Retorno: ORA-02291: integrity constraint (FK_TB_VENDA_CLIENTE) violated
INSERT INTO tb_venda (id_cliente, id_vendedor, dt_venda, status, canal)
VALUES (9999, 1, SYSDATE, 'ABERTA', 'LOJA');

/*
   A fk_tb_venda_cliente existe justamente pra evitar "venda órfã": aquela venda
   que aparece no relatório mas ninguém sabe de quem é. Se o cliente não está
   na tabela, a venda não entra — e é isso que mantém o CRM e as métricas
   comerciais confiáveis.
*/

-- Questão 2: Violação de Domínio (CHECK)
-- 'PENDENTE' não faz parte do vocabulário de status do modelo.
-- Retorno: ORA-02290: check constraint (CK_TB_VENDA_STATUS) violated
UPDATE tb_venda
SET status = 'PENDENTE'
WHERE id_venda = 1;

/*
   O ck_tb_venda_status só aceita 'ABERTA', 'FECHADA' ou 'CANCELADA'. Repare que
   a validação mora no banco, não na interface: se um bug, um script improvisado
   ou uma integração externa tentar forçar outro valor, o banco barra na hora.
   No aplicativo o dado sujo ainda passaria por um eventual pulo no front-end;
   no banco ele simplesmente não entra.
*/

-- Questão 3: Impedindo Preços Absurdos
-- Preço negativo distorceria qualquer dashboard de receita.
-- Retorno: ORA-02290: check constraint (CK_TB_PRODUTO_PRECO) violated
INSERT INTO tb_produto (id_categoria, sku, nome, preco_unit)
VALUES (1, 'SKU-TEMP-01', 'Produto Teste Negativo', -15.00);

/*
   O ck_tb_produto_preco (preco_unit > 0) derruba a inserção. Vale pra dois
   cenários comuns: o famoso erro de digitação (esqueceu o sinal, trocou a
   vírgula) e o malandro que tenta lançar preço negativo pra "ganhar" no
   inventário. Um preço de -15.00 viraria crédito fantasma na receita.
*/

-- ---------------------------------------------------------------------
-- PARTE 2: EVOLUINDO A MODELAGEM FÍSICA (DDL)
-- ---------------------------------------------------------------------

-- Questão 4: Limite de Desconto de Itens (CHECK)
-- Desconto de item não pode passar de 50% do preço unitário.
ALTER TABLE tb_venda_item
ADD CONSTRAINT ck_tb_item_desconto_max
CHECK (desconto_item <= (preco_unit * 0.50));

/*
   No Oracle o CHECK compara colunas da mesma linha sem enroscos — e é exatamente
   isso que a regra pede: o desconto contra o preço unitário daquele item. Detalhe
   que o professor cobra: CHECK não subquery, não dá pra consultar tb_produto daqui
   dentro. Usar o preco_unit da linha tem ainda um lado bom — é o preço congelado
   na venda, que é o que interessa na hora de conceder o desconto.
*/

-- Questão 5: Garantia de Unicidade de Contato (UNIQUE)
-- Dois clientes, o mesmo telefone = alguém digitou errado ou está fingindo.
ALTER TABLE tb_cliente
ADD CONSTRAINT uq_tb_cliente_telefone UNIQUE (telefone);

/*
   O UNIQUE gera um índice exclusivo por baixo e não deixa o telefone repetir.
   A pegadinha (que o gabarito reforça): NULL escapa da unicidade — vários
   clientes podem ficar sem telefone, mas se preencherem, tem que ser único.
   E se já houver duplicatas na base, o ALTER falha; limpe antes.
*/

-- ---------------------------------------------------------------------
-- PARTE 3: CASCADE VS. SOFT DELETE
-- ---------------------------------------------------------------------

-- Questão 6: Exclusão em Cascata (ON DELETE CASCADE)
-- A venda some e o Oracle varre os itens junto, sozinho.
DELETE FROM tb_venda WHERE id_venda = 1;

-- Conferindo que os filhos foram limpos automaticamente:
SELECT * FROM tb_venda_item WHERE id_venda = 1;

/*
   A fk_item_venda foi criada com ON DELETE CASCADE, então ao apagar a venda pai
   o Oracle percorre tb_venda_item e apaga tudo que aponta pra ela. Automático e
   sem erro — que é também o lado perigoso: um DELETE sem WHERE levaria venda e
   itens junto num piscar de olhos. Protege contra dado inconsistente, mas
   exige transação e um backup por perto.
*/

-- Questão 7: Exclusão Lógica (Soft Delete)
-- Vendedor desligou? Vira 'N', não vira NULL e não vira DELETE.
UPDATE tb_vendedor
SET ativo = 'N'
WHERE id_vendedor = 1;

/*
   Apagar um vendedor (ou cliente, ou produto) com histórico de faturamento é
   pedir problema: as vendas dele referenciam a PK por FK — ou o DELETE falha,
   ou leva o histórico junto. O soft delete inativa o cadastro pra novos
   lançamentos (o CHECK ck_tb_vendedor_ativo garante que só 'S'/'N' circule)
   e mantém o histórico inteiro em pé. No fim das contas é a pergunta de sempre:
   apagar de verdade ou só parar de usar? Aqui, só para de usar.
*/
