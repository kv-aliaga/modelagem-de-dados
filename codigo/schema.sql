-- SET INFORMAÇÕES DE FORMATAÇÃO
ALTER DATABASE db_banco_trabalho SET TIMEZONE TO 'America/Sao_Paulo';
ALTER DATABASE db_banco_trabalho SET datestyle = 'ISO, DMY';

-- EXCLUI SCHEMAS E RECRIA ELES
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS log CASCADE;
CREATE SCHEMA public;
CREATE SCHEMA log;

-- CRIA TABELAS DO SCHEMA PUBLIC
CREATE TABLE tb_loja(
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cnpj VARCHAR(14) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    telefone VARCHAR(20) UNIQUE,
    percentual_comissao NUMERIC(4,2) NOT NULL CHECK ( percentual_comissao > 0 ),
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW()
);

CREATE TABLE tb_banco (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cnpj CHAR(14) UNIQUE NOT NULL,
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW()
);

CREATE TABLE tb_funcionario (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cpf VARCHAR(11) UNIQUE NOT NULL ,
    cargo VARCHAR(50) NOT NULL ,
    salario NUMERIC(15,2) NOT NULL CHECK ( salario > 0 ),
    email VARCHAR(255) UNIQUE NOT NULL,
    telefone VARCHAR(20) UNIQUE,
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW(),
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id)
);

CREATE TABLE tb_conta (
    id BIGSERIAL PRIMARY KEY,
    agencia VARCHAR(10) NOT NULL,
    numero_conta VARCHAR(8) UNIQUE NOT NULL,
    tipo_conta VARCHAR(30) NOT NULL CHECK ( tipo_conta IN ('CORRENTE', 'POUPANCA', 'SALARIO') ),
    saldo NUMERIC(15,2) NOT NULL CHECK ( saldo >= 0 ),
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW(),
    cod_banco BIGINT NOT NULL REFERENCES tb_banco (id)
);

CREATE TABLE tb_pagamento(
    id BIGSERIAL PRIMARY KEY,
    tipo_pagamento VARCHAR(30) NOT NULL CHECK ( tipo_pagamento IN ('BOLETO', 'PIX', 'DEBITO', 'CREDITO')),
    status_pagamento VARCHAR(30) NOT NULL CHECK ( status_pagamento IN ('AGUARDANDO', 'CONCLUIDO', 'EXPIRADO', 'CANCELADO') ),
    valor NUMERIC(15,2) NOT NULL CHECK ( valor > 0 ),
    data_pagamento TIMESTAMP DEFAULT NOW(),
    cod_conta_origem BIGINT NOT NULL REFERENCES tb_conta (id),
    cod_conta_destino BIGINT NOT NULL REFERENCES tb_conta (id)
);

CREATE TABLE tb_venda (
    id BIGSERIAL PRIMARY KEY,
    valor_total NUMERIC(15,2) NOT NULL CHECK ( valor_total > 0 ),
    status_venda VARCHAR(30) NOT NULL CHECK ( status_venda IN ('APROVADO', 'CANCELADO', 'ESTORNADO') ),
    data_venda TIMESTAMP DEFAULT NOW(),
    cod_vendedor BIGINT NOT NULL REFERENCES tb_funcionario (id),
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id)
);

CREATE TABLE tb_transportadora (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cnpj CHAR(14) UNIQUE NOT NULL,
    telefone VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE NOT NULL,
    taxa_entrega NUMERIC(10,2) NOT NULL CHECK ( taxa_entrega > 0 ),
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW()
);

-- TABELAS DE LIGAÇÃO
CREATE TABLE tb_envia_itens (
    id BIGSERIAL PRIMARY KEY,
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id),
    cod_transportadora BIGINT NOT NULL REFERENCES tb_transportadora (id)
);

CREATE TABLE tb_conta_loja (
    id BIGSERIAL PRIMARY KEY,
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id),
    cod_conta BIGINT NOT NULL REFERENCES tb_conta (id)
);

CREATE TABLE tb_conta_funcionario (
    id BIGSERIAL PRIMARY KEY,
    cod_funcionario BIGINT NOT NULL REFERENCES tb_funcionario (id),
    cod_conta BIGINT NOT NULL REFERENCES tb_conta (id)
);

CREATE TABLE tb_pagamento_parcelado (
    id BIGSERIAL PRIMARY KEY,
    cod_pagamento BIGINT NOT NULL REFERENCES tb_pagamento (id),
    cod_venda BIGINT NOT NULL REFERENCES tb_venda (id)
);

-- TABELAS DE LOG
CREATE TABLE log.tb_log_geral (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(60) NOT NULL,
    tabela VARCHAR(60) NOT NULL,
    acao VARCHAR(6) NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW()
);


CREATE TABLE log.tb_log_conta(
    id BIGSERIAL PRIMARY KEY,
    id_log_geral INT NOT NULL REFERENCES log.tb_log_geral(id),
    id_conta BIGINT REFERENCES tb_conta(id),
    old_saldo NUMERIC(15,2),
    new_saldo NUMERIC(15,2),
    old_tipo_conta VARCHAR(13),
    new_tipo_conta VARCHAR(13),
    old_ativo BOOLEAN,
    new_ativo BOOLEAN
);

CREATE TABLE log.tb_log_venda(
    id BIGSERIAL PRIMARY KEY,
    id_log_geral INT NOT NULL REFERENCES log.tb_log_geral(id),
    id_venda BIGINT REFERENCES tb_venda(id),
    old_status_venda VARCHAR(30),
    new_status_venda VARCHAR(30)
);

-- FUNÇÕES
CREATE OR REPLACE FUNCTION fn_is_different(v_campo_old ANYELEMENT, v_campo_new ANYELEMENT)
    RETURNS ANYELEMENT
    LANGUAGE plpgsql AS $$
BEGIN
    IF v_campo_new IS DISTINCT FROM v_campo_old THEN
        RETURN v_campo_new;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION get_qtd_vendas(p_id BIGINT, p_status VARCHAR(30), is_loja BOOLEAN)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
   DECLARE v_qtd_vendas INTEGER;
   BEGIN
       IF p_status NOT IN ('APROVADO', 'ESTORNADO', 'CANCELADO') THEN
           RAISE EXCEPTION 'Status inválido';
       END IF;

       IF is_loja THEN
           SELECT COUNT(*)
           INTO v_qtd_vendas
           FROM tb_venda
           WHERE cod_loja = p_id AND status_venda = p_status;
       ELSE
           SELECT COUNT(*)
           INTO v_qtd_vendas
           FROM tb_venda
           WHERE cod_vendedor = p_id AND status_venda = p_status;
       END IF;

       RETURN v_qtd_vendas;
   END;
$$;

CREATE OR REPLACE FUNCTION get_total_vendido(p_id BIGINT, p_status VARCHAR(30), is_loja BOOLEAN)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
    DECLARE v_total_vendas NUMERIC;
    BEGIN
        IF p_status NOT IN ('APROVADO', 'ESTORNADO', 'CANCELADO') THEN
            RAISE EXCEPTION 'Status inválido';
        END IF;

        IF is_loja THEN
            SELECT (SUM(valor_total))
            INTO v_total_vendas
            FROM tb_venda
            WHERE cod_loja = p_id AND status_venda = p_status;
        ELSE
            SELECT (SUM(valor_total))
            INTO v_total_vendas
            FROM tb_venda
            WHERE cod_vendedor = p_id AND status_venda = p_status;
        END IF;

        RETURN v_total_vendas;
    END;
$$;

CREATE OR REPLACE FUNCTION fn_conta_esta_ativa(p_cod_conta BIGINT)
    RETURNS BOOLEAN
    LANGUAGE plpgsql AS
$$
DECLARE
    v_ativo BOOLEAN;
BEGIN
    SELECT ativo INTO v_ativo FROM tb_conta WHERE id = p_cod_conta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conta não encontrada';
    END IF;

    IF NOT v_ativo THEN
        RAISE EXCEPTION 'Conta inativa';
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
        RAISE EXCEPTION 'Conta não encontrada';
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
        RAISE EXCEPTION 'Comissão não encontrada';
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
        RAISE EXCEPTION 'Venda não encontrada';
    END IF;

    IF v_status_venda <> 'APROVADO' THEN
        RAISE EXCEPTION 'Status inválido';
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
    VALUES (CURRENT_USER, p_tabela,p_acao, NOW());
END;
$$;

-- VIEWS
CREATE OR REPLACE VIEW vw_vendas_por_loja AS
    SELECT
        l.id as id_loja,
        l.nome as loja,
        l.percentual_comissao,
        get_qtd_vendas(l.id, 'APROVADO', TRUE) AS qtd_vendas_aprovadas,
        COALESCE(get_qtd_vendas(l.id, 'ESTORNADO', TRUE), 0) AS qtd_vendas_estornadas,
        COALESCE(get_qtd_vendas(l.id, 'CANCELADO', TRUE), 0) AS qtd_vendas_canceladas,

        get_total_vendido(l.id, 'APROVADO', TRUE) AS total_vendido,
        COALESCE(get_total_vendido(l.id, 'ESTORNADO', TRUE), 0) AS total_estornado,
        COALESCE(get_total_vendido(l.id, 'CANCELADO', TRUE), 0) AS total_cancelado,

        (
             get_total_vendido(l.id, 'APROVADO', TRUE) -
             COALESCE(get_total_vendido(l.id, 'ESTORNADO', TRUE), 0)
        ) AS venda_bruta,

        (
            get_total_vendido(l.id, 'APROVADO', TRUE) -
            COALESCE(get_total_vendido(l.id, 'ESTORNADO', TRUE), 0)
        ) * l.percentual_comissao AS valor_comissao,

        (
            SELECT SUM(t.taxa_entrega) 
            FROM tb_envia_itens e 
            JOIN tb_transportadora t ON t.id = e.cod_transportadora
            WHERE e.cod_loja = l.id
        ) AS taxa_entrega,

        (
            get_total_vendido(l.id, 'APROVADO', TRUE) - COALESCE(get_total_vendido(l.id, 'ESTORNADO', TRUE), 0) -
            (SELECT SUM(t.taxa_entrega) 
                FROM tb_envia_itens e 
                JOIN tb_transportadora t ON t.id = e.cod_transportadora 
                WHERE e.cod_loja = l.id
            )) AS saldo_liquido

    FROM tb_loja l
    WHERE l.ativo = TRUE
    ORDER BY venda_bruta DESC;

CREATE OR REPLACE VIEW vw_vendas_por_vendedor AS
    SELECT
        f.id AS id_vendedor,
        f.nome AS vendedor,
        f.cargo,
        l.nome AS loja,
        COUNT(v.id) AS total_vendas,

        get_qtd_vendas(f.id, 'APROVADO', FALSE) AS qtd_vendas_aprovadas,
        COALESCE(get_qtd_vendas(f.id, 'ESTORNADO', FALSE), 0) AS qtd_vendas_estornadas,
        COALESCE(get_qtd_vendas(f.id, 'CANCELADO', FALSE), 0) AS qtd_vendas_canceladas,

        get_total_vendido(f.id, 'APROVADO', FALSE) AS total_vendido,
        COALESCE(get_total_vendido(f.id, 'ESTORNADO', FALSE), 0) AS total_estornado,
        COALESCE(get_total_vendido(f.id, 'CANCELADO', FALSE), 0) AS total_cancelado,

        (
            get_total_vendido(f.id, 'APROVADO', FALSE) -
            COALESCE(get_total_vendido(f.id, 'ESTORNADO', FALSE), 0)
            ) AS venda_bruta,

        (
            get_total_vendido(f.id, 'APROVADO', FALSE) -
            COALESCE(get_total_vendido(f.id, 'ESTORNADO', FALSE), 0)
            ) * l.percentual_comissao AS valor_comissao

    FROM tb_funcionario f
    JOIN tb_loja l ON l.id = f.cod_loja
    JOIN tb_venda v ON v.cod_vendedor = f.id
    WHERE f.ativo = true
    GROUP BY f.id, f.nome, f.cargo, l.nome, l.percentual_comissao
    ORDER BY venda_bruta DESC;

CREATE OR REPLACE VIEW vw_contas_por_loja AS
    SELECT
        l.id as id_loja,
        l.nome as loja,
        b.nome as banco,
        c.agencia,
        c.numero_conta,
        c.tipo_conta,
        c.saldo,
        c.ativo as conta_ativa
    FROM tb_loja l
    JOIN tb_conta_loja cl ON cl.cod_loja = l.id
    JOIN tb_conta c ON c.id = cl.cod_conta
    JOIN tb_banco b ON b.id = c.cod_banco
    WHERE l.ativo = TRUE
    ORDER BY l.nome, c.saldo DESC;

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
BEGIN
    IF p_cod_conta_origem = p_cod_conta_destino THEN
        RAISE EXCEPTION 'As contas de origem e destino precisam ser diferentes';
    END IF;

    IF p_valor <= 0 THEN
        RAISE EXCEPTION 'O valor do pagamento preisa ser maior que zero';
    END IF;

    PERFORM fn_conta_esta_ativa(p_cod_conta_origem);
    PERFORM fn_conta_esta_ativa(p_cod_conta_destino);

    IF NOT fn_tem_saldo_suficiente(p_cod_conta_origem, p_valor) THEN
        RAISE EXCEPTION 'Saldo insuficiente na conta de origem';
    END IF;
    UPDATE tb_conta
    SET saldo            = saldo - p_valor,
        data_atualizacao = NOW()
    WHERE id = p_cod_conta_origem;

    UPDATE tb_conta
    SET saldo            = saldo + p_valor,
        data_atualizacao = NOW()
    WHERE id = p_cod_conta_destino;

    INSERT INTO tb_pagamento (tipo_pagamento, status_pagamento, valor, data_pagamento, cod_conta_origem, cod_conta_destino)
    VALUES (p_tipo_pagamento, 'CONCLUIDO', p_valor, NOW(), p_cod_conta_origem, p_cod_conta_destino)
    RETURNING id INTO v_id_pagamento;

    PERFORM fn_registrar_log('tb_pagamento', 'INSERT');
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

    SELECT f.id, f.cod_loja
    INTO v_cod_funcionario, v_cod_loja
    FROM tb_venda       v
    JOIN tb_funcionario f ON f.id = v.cod_vendedor
    WHERE v.id = p_cod_venda;
    SELECT cod_conta INTO v_cod_conta_loja
    FROM tb_conta_loja
    WHERE cod_loja = v_cod_loja
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loja não tem contas';
    END IF;

    SELECT cod_conta INTO v_cod_conta_func
    FROM tb_conta_funcionario
    WHERE cod_funcionario = v_cod_funcionario
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Funcionário não tem contas';
    END IF;

    v_comissao := fn_calcular_comissao_venda(p_cod_venda);

    CALL prc_processar_pagamento(v_cod_conta_loja, v_cod_conta_func, v_comissao, 'DEBITO');
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
    SELECT valor_total INTO v_valor_venda_real FROM tb_venda WHERE id = p_cod_venda;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venda não existe';
    END IF;

    IF p_valor <> v_valor_venda_real THEN
        RAISE EXCEPTION 'O valor (R$ %) não é o valor da venda (R$ %).',
            p_valor, v_valor_venda_real;
    END IF;
    PERFORM fn_venda_esta_aprovada(p_cod_venda);

    CALL prc_processar_pagamento(p_cod_conta_origem, p_cod_conta_destino, p_valor, p_tipo_pagamento);
    CALL prc_pagar_comissao_vendedor(p_cod_venda);

    END;
$$;

CREATE OR REPLACE PROCEDURE prc_cancelar_venda(p_cod_venda BIGINT)
    LANGUAGE plpgsql AS
$$
DECLARE
    v_status_venda     VARCHAR(30);
    v_valor_venda      NUMERIC(15,2);
    v_comissao         NUMERIC(15,2);
    v_cod_funcionario  BIGINT;
    v_conta_cliente    BIGINT;
    v_conta_loja       BIGINT;
    v_conta_vendedor   BIGINT;
BEGIN
    SELECT status_venda, valor_total, cod_vendedor
    INTO v_status_venda, v_valor_venda, v_cod_funcionario
    FROM tb_venda
    WHERE id = p_cod_venda;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venda não encontrada';
    END IF;

    IF v_status_venda = 'CANCELADO' OR v_status_venda = 'ESTORNADO' THEN
        RAISE EXCEPTION 'Esta venda ja foi cancelada ou estornada';
    END IF;

    SELECT p.cod_conta_origem, p.cod_conta_destino
    INTO v_conta_cliente, v_conta_loja
    FROM tb_pagamento p
    LEFT JOIN tb_pagamento_parcelado pp ON pp.cod_pagamento = p.id
    WHERE (pp.cod_venda = p_cod_venda OR p.valor = v_valor_venda) AND p.status_pagamento = 'CONCLUIDO'
    ORDER BY p.data_pagamento DESC
    LIMIT 1;

    SELECT cod_conta INTO v_conta_vendedor
    FROM tb_conta_funcionario
    WHERE cod_funcionario = v_cod_funcionario
    LIMIT 1;
    
    v_comissao := fn_calcular_comissao_venda(p_cod_venda);

    BEGIN
        UPDATE tb_venda
        SET status_venda = 'CANCELADO',
            data_venda   = NOW()
        WHERE id = p_cod_venda;

        CALL prc_processar_pagamento(v_conta_loja, v_conta_cliente, v_valor_venda, 'DEBITO');
        CALL prc_processar_pagamento(v_conta_vendedor, v_conta_loja, v_comissao, 'DEBITO');
        PERFORM fn_registrar_log('tb_venda', 'UPDATE');
    END;
END;
$$;

-- TRIGGERS
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
            INSERT INTO log.tb_log_conta(id_log_geral, id_conta, old_saldo, new_saldo, old_tipo_conta, new_tipo_conta, old_ativo, new_ativo)
            VALUES (v_id_log,
                    OLD.id,
                    OLD.saldo,
                    fn_is_different(OLD.saldo, NEW.saldo),
                    OLD.tipo_conta,
                    fn_is_different(OLD.tipo_conta, NEW.tipo_conta),
                    OLD.ativo,
                    fn_is_different(OLD.ativo,NEW.ativo)
                );

        ELSIF tg_op = 'INSERT' THEN
            INSERT INTO log.tb_log_conta(id_log_geral, id_conta, new_saldo, new_tipo_conta, new_ativo)
            VALUES (v_id_log, NEW.id, NEW.saldo, NEW.tipo_conta, NEW.ativo);
        ELSE
            INSERT INTO log.tb_log_conta(id_log_geral, id_conta, old_saldo, old_tipo_conta, old_ativo)
            VALUES (v_id_log, OLD.id, OLD.saldo, OLD.tipo_conta, OLD.ativo);
        END IF;

        IF tg_op = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
    END;
$$;

CREATE OR REPLACE FUNCTION log.fn_auditoria_venda()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id_log INT;
BEGIN
    INSERT INTO log.tb_log_geral(usuario, tabela, acao)
    VALUES (CURRENT_USER, TG_TABLE_NAME, TG_OP)
    RETURNING id INTO v_id_log;

    IF TG_OP = 'UPDATE' THEN
        INSERT INTO log.tb_log_venda(id_log_geral, id_venda, old_status_venda, new_status_venda)
        VALUES (v_id_log, OLD.id, OLD.status_venda, fn_is_different(OLD.status_venda, NEW.status_venda));
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO log.tb_log_venda(id_log_geral, id_venda, new_status_venda)
        VALUES (v_id_log, NEW.id, NEW.status_venda);
    ELSE
        INSERT INTO log.tb_log_venda(id_log_geral, id_venda, old_status_venda)
        VALUES (v_id_log, OLD.id, OLD.status_venda);
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD;
    ELSE RETURN NEW;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_impedir_venda_vendedor_inativo()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS $$
DECLARE v_Ativo BOOLEAN;
BEGIN
    SELECT ativo INTO v_Ativo FROM tb_funcionario WHERE id = NEW.cod_vendedor;

    IF NOT v_ativo THEN
        RAISE EXCEPTION 'Vendedor inativo';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trg_valida_pagamento_status()
    RETURNS TRIGGER
    LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status_pagamento = 'CONCLUIDO' AND NEW.status_pagamento = 'AGUARDANDO' OR
       OLD.status_pagamento = 'CANCELADO' AND NEW.status_pagamento = 'CONCLUIDO' THEN
        RAISE EXCEPTION 'Status inválido';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER tg_auditoria_conta
    AFTER INSERT OR UPDATE OR DELETE ON tb_conta
    FOR EACH ROW EXECUTE FUNCTION log.fn_auditoria_conta();

CREATE OR REPLACE TRIGGER tg_auditoria_venda
    AFTER INSERT OR UPDATE OR DELETE ON tb_venda
    FOR EACH ROW EXECUTE FUNCTION log.fn_auditoria_venda();

CREATE TRIGGER trg_impedir_venda_vendedor_inativo
    BEFORE INSERT ON tb_venda
    FOR EACH ROW EXECUTE FUNCTION fn_trg_impedir_venda_vendedor_inativo();

CREATE OR REPLACE TRIGGER trg_valida_pagamento_status
    BEFORE UPDATE ON tb_pagamento
    FOR EACH ROW EXECUTE FUNCTION fn_trg_valida_pagamento_status();