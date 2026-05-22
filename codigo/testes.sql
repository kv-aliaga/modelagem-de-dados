-- Teste das functions
SELECT fn_conta_esta_ativa(1);
SELECT fn_tem_saldo_suficiente(1, 500.00);
SELECT fn_tem_saldo_suficiente(1, 99999.00);
SELECT fn_calcular_comissao_venda(1);
SELECT fn_venda_esta_aprovada(1);
SELECT get_qtd_vendas(1, 'APROVADO', TRUE);
SELECT get_total_vendido(1, 'APROVADO', TRUE);

-- Teste das views
SELECT * FROM vw_vendas_por_loja;
SELECT * FROM vw_vendas_por_vendedor;
SELECT * FROM vw_contas_por_loja;

-- Teste das procedures
CALL prc_processar_pagamento(1, 2, 100.00, 'PIX');
CALL prc_finalizar_venda(1, 1, 2, 231.79, 'PIX');
CALL prc_cancelar_venda(1);

-- Triggers
SELECT * FROM log.tb_log_geral ORDER BY id;
SELECT * FROM log.tb_log_conta ORDER BY id;
SELECT * FROM log.tb_log_venda ORDER BY id;

-- Testes de erro
CALL prc_processar_pagamento(1, 1, 100.00, 'PIX');
CALL prc_processar_pagamento(1, 2, 0.00, 'PIX');
SELECT fn_conta_esta_ativa(99999);
CALL prc_cancelar_venda(1);
CALL prc_finalizar_venda(1, 1, 2, 999.00, 'PIX');