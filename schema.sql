-- SET INFORMAÇÕES DE DATA E HORA
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
    cnpj CHAR(14) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    telefone VARCHAR(20) UNIQUE,
    percentual_comissao NUMERIC(4,2) NOT NULL CHECK ( percentual_comissao > 0 ),
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW()
);

CREATE TABLE tb_funcionario (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cpf CHAR(11) UNIQUE NOT NULL ,
    cargo VARCHAR(50) NOT NULL ,
    salario NUMERIC(15,2) NOT NULL CHECK ( salario > 0 ),
    email VARCHAR(255) UNIQUE NOT NULL,
    telefone VARCHAR(20) UNIQUE,
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW(),
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id)
);

CREATE TABLE tb_banco (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(60) NOT NULL,
    cnpj CHAR(14) UNIQUE NOT NULL,
    ativo BOOLEAN DEFAULT TRUE,
    data_criacao TIMESTAMP DEFAULT NOW(),
    data_atualizacao TIMESTAMP DEFAULT NOW()
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
    status_pagamento VARCHAR(30) NOT NULL CHECK ( status_pagamento IN ('AGUARDANDO', 'CONCLUIDO', 'EXPIRADO') ),
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
    cod_vendedor BIGINT NOT NULL REFERENCES tb_funcionario (id)
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

-- TABELAS UTILITÁRIAS (DE LIGAÇÃO)
CREATE TABLE tb_envia_itens (
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id),
    cod_transportadora BIGINT NOT NULL REFERENCES tb_transportadora (id)
);

CREATE TABLE tb_conta_loja (
    cod_loja BIGINT NOT NULL REFERENCES tb_loja (id),
    cod_conta BIGINT NOT NULL REFERENCES tb_conta (id)
);

CREATE TABLE tb_conta_funcionario (
    cod_funcionario BIGINT NOT NULL REFERENCES tb_funcionario (id),
    cod_conta BIGINT NOT NULL REFERENCES tb_conta (id)
);

CREATE TABLE tb_pagamento_parcelado (
    cod_pagamento BIGINT NOT NULL REFERENCES tb_pagamento (id),
    cod_venda BIGINT NOT NULL REFERENCES tb_venda (id)
);


-- TABELAS DE LOG
CREATE TABLE log.tb_log_geral (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(60) NOT NULL,
    tabela VARCHAR(60) NOT NULL,
    acao VARCHAR(8) NOT NULL,
    timestamp TIMESTAMP
);