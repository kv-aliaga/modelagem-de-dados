

-- TODAS AS TABELAS DE LOG PRECISAM ESTAR NO SCHEMA log (indicados de forma log.tb_log_nome)
-- TODAS AS TABELAS DE LOG PRECISAM TER UMA FK DE log.tb_log_geral

-- TODAS AS TABELAS DE LOG PRECISAM TER ESSA ESTRUTURA:
-- id, fk de log geral, campos old e new APENAS dos campos que PODEM SER ALTERADOS

-- estrutura das funções de log (SEMPRE DENTRO DO SCHEMA log!):
-- inserir na tabela de log geral
-- colocar return na variável criada
-- fazer um "match-case" com if e else com o nome da ação
-- caso for update: inserir OLD e NEW (utilizar a função fn_is_different() para validar)
-- caso for inserir: inserir apenas campos NEW
-- caso for delete: inserir apenas campos OLD
-- retorno da function: se for delete OLD, se não NEW

-- estrutura da trigger: AFTER INSERT OR UPDATE OR DELETE

CREATE TABLE log.tb_log_conta(
                                 id BIGSERIAL PRIMARY KEY,
                                 id_log_geral INT NOT NULL REFERENCES log.tb_log_geral(id),
                                 old_saldo NUMERIC(15,2),
                                 new_saldo NUMERIC(15,2),
                                 old_tipo_conta VARCHAR(13),
                                 new_tipo_conta VARCHAR(13),
                                 old_ativo BOOLEAN,
                                 new_ativo BOOLEAN
);

-- EXEMPLO:
CREATE OR REPLACE FUNCTION fn_is_different(v_campo_old ANYELEMENT, v_campo_new ANYELEMENT)
    RETURNS VARCHAR(60)
    LANGUAGE plpgsql AS $$
BEGIN
    IF v_campo_new IS DISTINCT FROM v_campo_old THEN
        RETURN v_campo_new;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION log.fn_auditoria_conta()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS $$
DECLARE
    v_id_log INT;

BEGIN
    INSERT INTO log.tb_log_geral(usuario, tabela, acao)
    VALUES (current_user, tg_table_name, tg_op)
    RETURNING id INTO v_id_log;

    IF tg_op = 'UPDATE' THEN
        INSERT INTO log.tb_log_conta(id_log_geral, old_saldo, new_saldo, old_tipo_conta, new_tipo_conta, old_ativo, new_ativo)
        VALUES (v_id_log,
                OLD.saldo,
                fn_is_different(OLD.saldo, NEW.saldo),
                OLD.tipo_conta,
                fn_is_different(OLD.tipo_conta, NEW.tipo_conta),
                OLD.ativo,
                fn_is_different(OLD.ativo,NEW.ativo)
               );

    ELSIF tg_op = 'INSERT' THEN
        INSERT INTO log.tb_log_conta(id_log_geral, new_saldo, new_tipo_conta, new_ativo)
        VALUES (v_id_log, NEW.agencia, NEW.saldo, NEW.tipo_conta, NEW.ativo);
    ELSE
        INSERT INTO log.tb_log_conta(id_log_geral, old_saldo, old_tipo_conta, old_ativo)
        VALUES (v_id_log, OLD.agencia, OLD.saldo, OLD.tipo_conta, OLD.ativo);
    END IF;

    IF tg_op = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

CREATE OR REPLACE TRIGGER tg_auditoria_conta
    AFTER INSERT OR UPDATE OR DELETE ON tb_conta
    FOR EACH ROW EXECUTE FUNCTION log.fn_auditoria_conta();
