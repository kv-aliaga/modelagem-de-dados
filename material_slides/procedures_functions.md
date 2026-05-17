# Documentação de Banco de Dados: Functions e Procedures

Este documento apresenta a explicação detalhada da arquitetura lógica desenvolvida para o sistema de gerenciamento de vendas, comissões e movimentações financeiras.

---

## Functions Utilitárias
As *Functions* são blocos lógicos especializados em **validar regras de negócio** ou **realizar cálculos**. Elas funcionam como fiscais ou assistentes: não alteram o saldo diretamente, apenas respondem "verdadeiro/falso" ou devolvem um valor calculado.

### 1. `fn_conta_esta_ativa`
* **Propósito:** Garantir que nenhuma operação financeira seja realizada envolvendo contas inexistentes ou bloqueadas.
* **Como funciona:** Realiza uma busca na tabela `tb_conta` utilizando o ID fornecido. Se a conta não for encontrada ou se o campo `ativo` for falso (`FALSE`), o banco interrompe imediatamente a execução e lança uma exceção.
* **Benefício:** Evita transferências para contas desativadas.

### 2. `fn_tem_saldo_suficiente`
* **Propósito:** Validar a viabilidade financeira de uma transferência antes de debitar o valor.
* **Como funciona:** Consulta o saldo atual da conta de origem e compara com o valor solicitado para a transação. Retorna `TRUE` se houver saldo suficiente ou `FALSE` caso contrário.
* **Benefício:** Impede que contas fiquem com saldos negativos incoerentes com as restrições do banco.

### 3. `fn_calcular_comissao_venda`
* **Propósito:** Centralizar o cálculo de comissões de vendas para evitar erros manuais ou duplicidade de fórmulas.
* **Como funciona:** Faz um cruzamento de dados (`JOIN`) entre a venda, o funcionário que a realizou e a loja onde ele trabalha para capturar o `percentual_comissao`. Em seguida, aplica a porcentagem sobre o valor total da venda e arredonda o resultado para duas casas decimais.

### 4. `fn_venda_esta_aprovada`
* **Propósito:** Blindar o sistema para que ações financeiras só aconteçam em vendas legítimas.
* **Como funciona:** Verifica se o status da venda na tabela `tb_venda` é exatamente `'APROVADO'`. Se a venda estiver cancelada, estornada ou não existir, o processo é bloqueado na hora.

### 5. `fn_registrar_log`
* **Propósito:** Auditoria e segurança do banco de dados.
* **Como funciona:** Insere automaticamente um registro na tabela `log.tb_log_geral` contendo o usuário do sistema que executou a ação, a tabela modificada, o tipo de operação (`INSERT`, `UPDATE`, etc.) e o carimbo de data/hora atual (`NOW()`).

---

## Procedures (Processos de Negócio)
As *Procedures* executam as **ações e regras de negócio complexas**, modificando dados em múltiplas tabelas, alterando saldos e coordenando as funções descritas acima sob uma mesma transação segura.

### 1. `prc_processar_pagamento`
É o motor de movimentação bancária do ecossistema. Responsável por transferir valores de forma segura.
* **Fluxo de Execução:**
  1. Valida se a conta de origem e destino são diferentes.
  2. Garante que o valor da transferência é maior que zero.
  3. Executa as validações `fn_conta_esta_ativa` e `fn_tem_saldo_suficiente`.
  4. Deduz o valor da conta de origem e adiciona à conta de destino.
  5. Cria o registro oficial na tabela `tb_pagamento` com o status `'CONCLUIDO'`.
  6. Registra a operação no log de auditoria.
* **Segurança:** Possui um bloco `EXCEPTION` interno. Se o banco falhar ou faltar energia no meio do processo, tudo sofre um **Rollback** automático, garantindo que o dinheiro nunca suma ou fique duplicado.

### 2. `prc_pagar_comissao_vendedor`
Automatiza o repasse financeiro meritocrático ao funcionário que realizou a venda.
* **Fluxo de Execução:**
  1. Valida se a venda associada está devidamente aprovada.
  2. Localiza as respectivas contas bancárias da loja e do funcionário através das tabelas utilitárias (`tb_conta_loja` e `tb_conta_funcionario`).
  3. Invoca a função `fn_calcular_comissao_venda`.
  4. **Reutilização de Código:** Chama a procedure `prc_processar_pagamento` para transferir o valor calculado da conta da loja para a conta do funcionário sob o tipo de pagamento `'DEBITO'`.

### 3. `prc_finalizar_venda`
O processo principal que orquestra o fechamento de um pedido no caixa da empresa.
* **Fluxo de Execução:**
  1. **Anti-Fraude:** Compara se o valor enviado pelo sistema externo/caixa é rigorosamente igual ao valor total registrado na venda do banco de dados.
  2. Garante que a venda está qualificada para fechamento (`'APROVADO'`).
  3. Executa a cobrança principal: transfere o valor da compra da **Conta do Cliente** para a **Conta da Loja**.
  4. Executa o split de pagamento imediatamente: aciona a `prc_pagar_comissao_vendedor` para retirar a parte devida ao funcionário do caixa da loja e enviar para a conta dele.

### 4. `prc_cancelar_venda`
Realiza o gerenciamento de crise e logística reversa financeira quando uma venda precisa ser desfeita.
* **Fluxo de Execução:**
  1. Altera o status da venda para `'CANCELADO'`.
  2. Rastreia o pagamento original na tabela `tb_pagamento` para descobrir de qual conta o cliente pagou e em qual conta da loja o dinheiro caiu.
  3. **Estorno Principal:** Transfere o valor integral da compra de volta da **Conta da Loja** para a **Conta do Cliente**.
  4. **Estorno da Comissão:** Calcula a comissão daquela venda e faz o vendedor devolvê-la (transfere da **Conta do Funcionário** de volta para a **Conta da Loja**).
  5. Salva o histórico de alteração nos logs do sistema.