CREATE OR REPLACE FUNCTION get_qtd_vendas(p_id BIGINT, p_status VARCHAR(30), is_loja BOOLEAN)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
   DECLARE v_qtd_vendas INTEGER;
   BEGIN
       IF p_status NOT IN ('APROVADO', 'ESTORNADO', 'CANCELADO') THEN
           RAISE EXCEPTION 'Status precisa ser um valor válido';
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
            RAISE EXCEPTION 'Status precisa ser um valor válido';
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
        ) * l.percentual_comissao AS valor_comissao

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