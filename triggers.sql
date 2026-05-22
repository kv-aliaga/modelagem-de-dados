
-- TRIGGER: ESTORNO DE PAGAMENTO
CREATE OR REPLACE FUNCTION fn_trg_estornar_pagamento()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
DECLARE
    v_err_desc TEXT;
BEGIN
    -- Verifica se o pagamento está sendo cancelado
    IF NEW.status_pagamento = 'CANCELADO' AND OLD.status_pagamento = 'CONCLUIDO' THEN
        BEGIN
            -- Reverte o saldo da conta de origem (adiciona de volta)
            UPDATE tb_conta
            SET saldo            = saldo + NEW.valor,
                data_atualizacao = NOW()
            WHERE id = NEW.cod_conta_origem;

            -- Reverte o saldo da conta de destino (subtrai)
            UPDATE tb_conta
            SET saldo            = saldo - NEW.valor,
                data_atualizacao = NOW()
            WHERE id = NEW.cod_conta_destino;

            -- Registra o estorno no log
            PERFORM fn_registrar_log('tb_pagamento', 'ESTORNO');

            RAISE NOTICE 'Pagamento estornado com sucesso. [id_pagamento=%, valor=R$ %]', NEW.id, NEW.valor;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err_desc = MESSAGE_TEXT;
            RAISE EXCEPTION 'Falha ao estornar pagamento: %', v_err_desc;
        END;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_estornar_pagamento
AFTER UPDATE ON tb_pagamento
FOR EACH ROW
EXECUTE FUNCTION fn_trg_estornar_pagamento();


-- TRIGGER: AUDITORIA DE CONTA

CREATE OR REPLACE FUNCTION fn_trg_auditoria_conta()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
BEGIN
    -- Registra alterações em contas
    IF TG_OP = 'UPDATE' THEN
        IF NEW.saldo <> OLD.saldo OR NEW.ativo <> OLD.ativo THEN
            PERFORM fn_registrar_log('tb_conta', 'UPDATE');
        END IF;
    ELSIF TG_OP = 'INSERT' THEN
        PERFORM fn_registrar_log('tb_conta', 'INSERT');
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM fn_registrar_log('tb_conta', 'DELETE');
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auditoria_conta
AFTER INSERT OR UPDATE OR DELETE ON tb_conta
FOR EACH ROW
EXECUTE FUNCTION fn_trg_auditoria_conta();


-- TRIGGER: VALIDAÇÃO DE SALDO NEGATIVO

CREATE OR REPLACE FUNCTION fn_trg_validar_saldo_negativo()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
BEGIN
    IF NEW.saldo < 0 THEN
        RAISE EXCEPTION 'Operação rejeitada: Saldo não pode ser negativo. [conta_id=%, saldo=R$ %]', 
            NEW.id, NEW.saldo;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_saldo_negativo
BEFORE INSERT OR UPDATE ON tb_conta
FOR EACH ROW
EXECUTE FUNCTION fn_trg_validar_saldo_negativo();

-- TRIGGER: VALIDAÇÃO DE TRANSFERÊNCIA ENTRE MESMAS CONTAS

CREATE OR REPLACE FUNCTION fn_trg_validar_transferencia_mesma_conta()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
BEGIN
    -- Impede transferências para a mesma conta
    IF NEW.cod_conta_origem = NEW.cod_conta_destino THEN
        RAISE EXCEPTION 
            'Operação rejeitada: Conta de origem e destino não podem ser iguais. [conta_id=%]',
            NEW.cod_conta_origem;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_transferencia_mesma_conta
BEFORE INSERT OR UPDATE ON tb_pagamento
FOR EACH ROW
EXECUTE FUNCTION fn_trg_validar_transferencia_mesma_conta();



-- TRIGGER: ATUALIZAÇÃO AUTOMÁTICA DE SALDO APÓS PAGAMENTO CONCLUÍDO

CREATE OR REPLACE FUNCTION fn_trg_processar_pagamento()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
DECLARE
    v_saldo_origem NUMERIC;
    v_err_desc TEXT;
BEGIN
    -- Executa apenas quando pagamento é concluído
    IF NEW.status_pagamento = 'CONCLUIDO'
       AND (TG_OP = 'INSERT'
       OR OLD.status_pagamento IS DISTINCT FROM 'CONCLUIDO') THEN

        BEGIN
            -- Busca saldo atual da conta de origem
            SELECT saldo
            INTO v_saldo_origem
            FROM tb_conta
            WHERE id = NEW.cod_conta_origem;

            -- Verifica saldo suficiente
            IF v_saldo_origem < NEW.valor THEN
                RAISE EXCEPTION
                    'Saldo insuficiente para pagamento. [conta_id=%, saldo=R$ %, valor_pagamento=R$ %]',
                    NEW.cod_conta_origem,
                    v_saldo_origem,
                    NEW.valor;
            END IF;

            -- Debita conta origem
            UPDATE tb_conta
            SET saldo = saldo - NEW.valor,
                data_atualizacao = NOW()
            WHERE id = NEW.cod_conta_origem;

            -- Credita conta destino
            UPDATE tb_conta
            SET saldo = saldo + NEW.valor,
                data_atualizacao = NOW()
            WHERE id = NEW.cod_conta_destino;

            -- Registra log
            PERFORM fn_registrar_log('tb_pagamento', 'PROCESSAMENTO');

            RAISE NOTICE
                'Pagamento processado com sucesso. [id_pagamento=%, valor=R$ %]',
                NEW.id,
                NEW.valor;

        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err_desc = MESSAGE_TEXT;
            RAISE EXCEPTION 'Erro ao processar pagamento: %', v_err_desc;
        END;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_processar_pagamento
AFTER INSERT OR UPDATE ON tb_pagamento
FOR EACH ROW
EXECUTE FUNCTION fn_trg_processar_pagamento();

-- TRIGGER: IMPEDIR VENDA DE VENDEDOR INATIVO
CREATE OR REPLACE FUNCTION fn_trg_impedir_venda_vendedor_inativo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_Ativo BOOLEAN;
BEGIN 
    SELECT ativo INTO v_Ativo FROM tb_funcionario WHERE id = NEW.cod_vendendor;

    IF NOT v_ativo THEN 
        RAISE EXCEPTION 'Operação rejeitada: Vendedor inativo.' , NEW.cod_vendendor;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_impedir_venda_vendedor_inativo
    BEFORE INSERT ON tb_venda
    FOR EACH ROW EXECUTE FUNCTION fn_trg_impedir_venda_vendedor_inativo();

-- TRIGGER: PROTEÇÃO DE STATUS DO PAGAMENTO
CREATE OR REPLACE FUNCTION fn_trg_valida_pagamento_status();
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN 
    IF OLD.status_pagamento = 'CONCLUIDO' AND NEW.status_pagamento = 'AGUARDANDO' THEN
        RAISE EXCEPTION 'Falha de segurança: Um pagamento concluido não pode voltar a ser pendente.' OLD.id;
    END IF;

    IF OLD.status_pagamento = 'CANCELADO' AND NEW.status_pagamento = 'CONCLUIDO' THEN
        RAISE EXCEPTION 'Falha de segurança: Um pagamento cancelado não pode voltar a ser concluido diretamente.' OLD.id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_valida_pagamento_status
    BEFORE UPDATE ON tb_pagamento
    FOR EACH ROW EXECUTE FUNCTION fn_trg_valida_pagamento_status();