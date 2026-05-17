
-- FUNCTIONS UTILITÁRIAS

CREATE OR REPLACE FUNCTION fn_conta_esta_ativa(p_cod_conta BIGINT)
    RETURNS BOOLEAN
    LANGUAGE plpgsql AS
$$
DECLARE
    v_ativo BOOLEAN;
BEGIN
    -- Busca o status em uma única query para evitar múltiplos SELECTs
    SELECT ativo INTO v_ativo FROM tb_conta WHERE id = p_cod_conta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conta não encontrada. [id=%]', p_cod_conta;
    END IF;

    IF NOT v_ativo THEN
        RAISE EXCEPTION 'A conta informada está inativa. [id=%]', p_cod_conta;
    END IF;

    RETURN TRUE;
END;
$$;


CREATE OR REPLACE FUNCTION fn_tem_saldo_suficiente(p_cod_conta BIGINT, p_valor NUMERIC(15,2))
    RETURNS BOOLEAN
    LANGUAGE plpgsql AS
$$
DECLARE
    v_saldo NUMERIC(15,2);
BEGIN
    SELECT saldo INTO v_saldo FROM tb_conta WHERE id = p_cod_conta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conta não encontrada para checagem de saldo. [id=%]', p_cod_conta;
    END IF;

    RETURN v_saldo >= p_valor;
END;
$$;


CREATE OR REPLACE FUNCTION fn_calcular_comissao_venda(p_cod_venda BIGINT)
    RETURNS NUMERIC(15,2)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_valor_total         NUMERIC(15,2);
    v_percentual_comissao NUMERIC(4,2);
BEGIN
    SELECT v.valor_total, l.percentual_comissao
    INTO v_valor_total, v_percentual_comissao
    FROM tb_venda       v
    JOIN tb_funcionario f ON f.id = v.cod_vendedor
    JOIN tb_loja        l ON l.id = f.cod_loja
    WHERE v.id = p_cod_venda;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venda ou dados de comissão da loja não encontrados. [venda_id=%]', p_cod_venda;
    END IF;

    RETURN ROUND((v_valor_total * v_percentual_comissao / 100), 2);
END;
$$;


CREATE OR REPLACE FUNCTION fn_venda_esta_aprovada(p_cod_venda BIGINT)
    RETURNS BOOLEAN
    LANGUAGE plpgsql AS
$$
DECLARE
    v_status_venda VARCHAR(30);
BEGIN
    SELECT status_venda INTO v_status_venda FROM tb_venda WHERE id = p_cod_venda;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venda não encontrada. [id=%]', p_cod_venda;
    END IF;

    IF v_status_venda <> 'APROVADO' THEN
        RAISE EXCEPTION 'Operação negada. A venda não está com status APROVADO. [status_atual=%]', v_status_venda;
    END IF;

    RETURN TRUE;
END;
$$;


CREATE OR REPLACE FUNCTION fn_registrar_log(p_tabela VARCHAR(60), p_acao VARCHAR(8))
    RETURNS VOID
    LANGUAGE plpgsql AS
$$
BEGIN
    INSERT INTO log.tb_log_geral (usuario, tabela, acao, timestamp)
    VALUES (CURRENT_USER, p_tabela, UPPER(p_acao), NOW());
END;
$$;

-- PROCEDURES

CREATE OR REPLACE PROCEDURE prc_processar_pagamento(
    p_cod_conta_origem  BIGINT,
    p_cod_conta_destino BIGINT,
    p_valor             NUMERIC(15,2),
    p_tipo_pagamento    VARCHAR(30)
)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_id_pagamento BIGINT;
    v_err_desc     TEXT;
BEGIN
    -- Validações preliminares de integridade de negócio
    IF p_cod_conta_origem = p_cod_conta_destino THEN
        RAISE EXCEPTION 'A conta de origem não pode ser igual à conta de destino.';
    END IF;

    IF p_valor <= 0 THEN
        RAISE EXCEPTION 'O valor do pagamento deve ser maior que zero. [valor=%]', p_valor;
    END IF;

    PERFORM fn_conta_esta_ativa(p_cod_conta_origem);
    PERFORM fn_conta_esta_ativa(p_cod_conta_destino);

    IF NOT fn_tem_saldo_suficiente(p_cod_conta_origem, p_valor) THEN
        RAISE EXCEPTION 'Saldo insuficiente na conta de origem para esta transação. [id=%]', p_cod_conta_origem;
    END IF;

    -- Bloco de execução da transferência protegendo a integridade financeira
    BEGIN
        UPDATE tb_conta
        SET saldo            = saldo - p_valor,
            data_atualizacao = NOW()
        WHERE id = p_cod_conta_origem;

        UPDATE tb_conta
        SET saldo            = saldo + p_valor,
            data_atualizacao = NOW()
        WHERE id = p_cod_conta_destino;

        INSERT INTO tb_pagamento (tipo_pagamento, status_pagamento, valor, data_pagamento, cod_conta_origem, cod_conta_destino)
        VALUES (UPPER(p_tipo_pagamento), 'CONCLUIDO', p_valor, NOW(), p_cod_conta_origem, p_cod_conta_destino)
        RETURNING id INTO v_id_pagamento;

        PERFORM fn_registrar_log('tb_pagamento', 'INSERT');

        RAISE NOTICE 'Pagamento R$ % processado com sucesso. [id_pagamento=%]', p_valor, v_id_pagamento;

    EXCEPTION WHEN OTHERS THEN
        -- Captura detalhes do erro e relança para garantir o Rollback da transação externa
        GET STACKED DIAGNOSTICS v_err_desc = MESSAGE_TEXT;
        RAISE EXCEPTION 'Falha crítica ao processar movimentação bancária: %', v_err_desc;
    END;
END;
$$;


CREATE OR REPLACE PROCEDURE prc_pagar_comissao_vendedor(p_cod_venda BIGINT)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_cod_funcionario BIGINT;
    v_cod_loja        BIGINT;
    v_cod_conta_loja  BIGINT;
    v_cod_conta_func  BIGINT;
    v_comissao        NUMERIC(15,2);
BEGIN
    PERFORM fn_venda_esta_aprovada(p_cod_venda);

    -- Agrupa a busca do funcionário e da loja
    SELECT f.id, f.cod_loja
    INTO v_cod_funcionario, v_cod_loja
    FROM tb_venda       v
    JOIN tb_funcionario f ON f.id = v.cod_vendedor
    WHERE v.id = p_cod_venda;

    -- Busca a conta da loja
    SELECT cod_conta INTO v_cod_conta_loja
    FROM tb_conta_loja
    WHERE cod_loja = v_cod_loja
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Erro de Configuração: Nenhuma conta bancária vinculada à loja. [cod_loja=%]', v_cod_loja;
    END IF;

    -- Busca a conta do funcionário
    SELECT cod_conta INTO v_cod_conta_func
    FROM tb_conta_funcionario
    WHERE cod_funcionario = v_cod_funcionario
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Erro de Cadastro: Nenhuma conta bancária vinculada ao funcionário. [cod_funcionario=%]', v_cod_funcionario;
    END IF;

    -- Calcula o valor devido baseado nas taxas do schema
    v_comissao := fn_calcular_comissao_venda(p_cod_venda);

    -- REUSABILIDADE: Chama a procedure existente ao invés de reescrever updates e inserts manuais
    CALL prc_processar_pagamento(
        p_cod_conta_origem  => v_cod_conta_loja,
        p_cod_conta_destino => v_cod_conta_func,
        p_valor             => v_comissao,
        p_tipo_pagamento    => 'DEBITO'
    );

    RAISE NOTICE 'Comissão repassada com sucesso ao vendedor. [vendedor_id=% , Valor=R$ %]', v_cod_funcionario, v_comissao;
END;
$$;


CREATE OR REPLACE PROCEDURE prc_finalizar_venda(
    p_cod_venda         BIGINT,
    p_cod_conta_origem  BIGINT,
    p_cod_conta_destino BIGINT,
    p_valor             NUMERIC(15,2),
    p_tipo_pagamento    VARCHAR(30)
)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_valor_venda_real NUMERIC(15,2);
BEGIN
    -- Validação de segurança extra: O valor pago confere com o valor total registrado na venda?
    SELECT valor_total INTO v_valor_venda_real FROM tb_venda WHERE id = p_cod_venda;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'A venda informada não existe. [id=%]', p_cod_venda;
    END IF;

    IF p_valor <> v_valor_venda_real THEN
        RAISE EXCEPTION 'Divergência de valores. O valor informado (R$ %) difere do valor real da venda (R$ %).', 
            p_valor, v_valor_venda_real;
    END IF;

    -- Garante que o status atual permite o encerramento do ciclo
    PERFORM fn_venda_esta_aprovada(p_cod_venda);

    -- 1. Executa o pagamento principal do cliente para a loja
    CALL prc_processar_pagamento(
        p_cod_conta_origem  => p_cod_conta_origem,
        p_cod_conta_destino => p_cod_conta_destino,
        p_valor             => p_valor,
        p_tipo_pagamento    => p_tipo_pagamento
    );

    -- 2. Dispara automaticamente o split de comissão do vendedor cadastrado
    CALL prc_pagar_comissao_vendedor(
        p_cod_venda => p_cod_venda
    );

    RAISE NOTICE 'Fluxo de venda finalizado e integrado com sucesso. [venda_id=%]', p_cod_venda;
END;
$$;

CREATE OR REPLACE PROCEDURE prc_cancelar_venda(
    p_cod_venda BIGINT
)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_status_venda     VARCHAR(30);
    v_valor_venda      NUMERIC(15,2);
    v_comissao         NUMERIC(15,2);
    v_cod_funcionario  BIGINT;
    
    -- Variáveis para o estorno do pagamento principal
    v_conta_cliente    BIGINT;
    v_conta_loja       BIGINT;
    
    -- Variável para o estorno da comissão
    v_conta_vendedor   BIGINT;
    
    v_err_desc         TEXT;
BEGIN
    -- 1. CONTEXTO E VALIDAÇÕES DA VENDA
    SELECT status_venda, valor_total, cod_vendedor
    INTO v_status_venda, v_valor_venda, v_cod_funcionario
    FROM tb_venda
    WHERE id = p_cod_venda;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cancelamento abortado: Venda não encontrada. [id=%]', p_cod_venda;
    END IF;

    IF v_status_venda = 'CANCELADO' OR v_status_venda = 'ESTORNADO' THEN
        RAISE EXCEPTION 'Esta venda já se encontra cancelada ou estornada. [status=%]', v_status_venda;
    END IF;

    -- 2. LOCALIZAR O PAGAMENTO ORIGINAL PARA RASTREAR AS CONTAS
    -- Busca o último pagamento concluído onde a conta destino pertence à loja do vendedor
    SELECT p.cod_conta_origem, p.cod_conta_destino
    INTO v_conta_cliente, v_conta_loja
    FROM tb_pagamento p
    -- Uma forma de garantir que pegamos o pagamento certo é cruzar com a tabela utilitária de parcelas, se usada
    LEFT JOIN tb_pagamento_parcelado pp ON pp.cod_pagamento = p.id
    WHERE (pp.cod_venda = p_cod_venda OR p.valor = v_valor_venda)
      AND p.status_pagamento = 'CONCLUIDO'
    ORDER BY p.data_pagamento DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Não foi possível localizar o pagamento ativo desta venda para realizar o estorno.';
    END IF;

    -- 3. LOCALIZAR A CONTA DO VENDEDOR PARA ESTORNO DA COMISSÃO
    SELECT cod_conta INTO v_conta_vendedor
    FROM tb_conta_funcionario
    WHERE cod_funcionario = v_cod_funcionario
    LIMIT 1;
    
    -- Calcula quanto foi pago de comissão na época
    v_comissao := fn_calcular_comissao_venda(p_cod_venda);

    -- 4. BLOCO TRANSACIONAL DE ESTORNO
    BEGIN
        -- Passo A: Atualiza o status da venda
        UPDATE tb_venda
        SET status_venda = 'CANCELADO',
            data_venda   = NOW() -- Atualiza o timestamp da última modificação
        WHERE id = p_cod_venda;

        -- Passo B: Estorno do Pagamento Principal (Loja -> Cliente)
        -- Invertemos os parâmetros: Origem vira v_conta_loja e Destino vira v_conta_cliente
        CALL prc_processar_pagamento(
            p_cod_conta_origem  => v_conta_loja,
            p_cod_conta_destino => v_conta_cliente,
            p_valor             => v_valor_venda,
            p_tipo_pagamento    => 'DEBITO' -- Registra a saída do caixa da loja
        );

        -- Passo C: Estorno da Comissão (Vendedor -> Loja)
        -- Se o vendedor tiver saldo para devolver a comissão, o sistema recupera
        CALL prc_processar_pagamento(
            p_cod_conta_origem  => v_conta_vendedor,
            p_cod_conta_destino => v_conta_loja,
            p_valor             => v_comissao,
            p_tipo_pagamento    => 'DEBITO'
        );

        -- Passo D: Log do cancelamento da venda
        PERFORM fn_registrar_log('tb_venda', 'UPDATE');

        RAISE NOTICE 'Venda % cancelada com sucesso. Valores e comissões estornados.', p_cod_venda;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_desc = MESSAGE_TEXT;
        RAISE EXCEPTION 'Falha ao processar o estorno financeiro do cancelamento: %', v_err_desc;
    END;
END;
$$;