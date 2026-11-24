SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: nf_array_add(bigint[], bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.nf_array_add(a bigint[], b bigint[]) RETURNS bigint[]
    LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
    AS $$
DECLARE i int;
BEGIN
  IF a IS NULL OR cardinality(a) = 0 THEN RETURN b; END IF;
  IF b IS NULL OR cardinality(b) = 0 THEN RETURN a; END IF;
  FOR i IN 1..cardinality(b) LOOP
    a[i] := coalesce(a[i], 0) + coalesce(b[i], 0);
  END LOOP;
  RETURN a;
END $$;


--
-- Name: nf_hist_sum(bigint[]); Type: AGGREGATE; Schema: public; Owner: -
--

CREATE AGGREGATE public.nf_hist_sum(bigint[]) (
    SFUNC = public.nf_array_add,
    STYPE = bigint[]
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alert_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alert_policies (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    name character varying NOT NULL,
    metric character varying NOT NULL,
    tx_type character varying DEFAULT 'web'::character varying NOT NULL,
    tx_name character varying,
    target character varying,
    comparison character varying DEFAULT 'above'::character varying NOT NULL,
    threshold double precision NOT NULL,
    window_minutes integer DEFAULT 5 NOT NULL,
    min_samples integer DEFAULT 10 NOT NULL,
    webhook_url character varying,
    enabled boolean DEFAULT true NOT NULL,
    last_evaluated_at timestamp(6) without time zone,
    last_value double precision,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: alert_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.alert_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: alert_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.alert_policies_id_seq OWNED BY public.alert_policies.id;


--
-- Name: api_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    oauth_client_id bigint,
    kind character varying NOT NULL,
    name character varying,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_tokens_id_seq OWNED BY public.api_tokens.id;


--
-- Name: app_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    tx_type character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    total double precision DEFAULT 0.0 NOT NULL,
    min double precision,
    max double precision,
    sumsq double precision DEFAULT 0.0 NOT NULL,
    errors_count bigint DEFAULT 0 NOT NULL,
    apdex_s bigint DEFAULT 0 NOT NULL,
    apdex_t bigint DEFAULT 0 NOT NULL,
    apdex_f bigint DEFAULT 0 NOT NULL,
    queue_total double precision DEFAULT 0.0 NOT NULL,
    t_middleware double precision DEFAULT 0.0 NOT NULL,
    t_controller double precision DEFAULT 0.0 NOT NULL,
    t_view double precision DEFAULT 0.0 NOT NULL,
    t_activerecord double precision DEFAULT 0.0 NOT NULL,
    t_database double precision DEFAULT 0.0 NOT NULL,
    t_external double precision DEFAULT 0.0 NOT NULL,
    t_cache double precision DEFAULT 0.0 NOT NULL,
    t_custom double precision DEFAULT 0.0 NOT NULL,
    t_job double precision DEFAULT 0.0 NOT NULL,
    t_graphql double precision DEFAULT 0.0 NOT NULL,
    hist bigint[] DEFAULT '{}'::bigint[] NOT NULL
);


--
-- Name: app_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_rollups_id_seq OWNED BY public.app_rollups.id;


--
-- Name: apps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.apps (
    id bigint NOT NULL,
    name character varying NOT NULL,
    api_key character varying NOT NULL,
    apdex_t double precision DEFAULT 500.0 NOT NULL,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: apps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.apps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: apps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.apps_id_seq OWNED BY public.apps.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: deployments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deployments (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    revision character varying NOT NULL,
    deployed_at timestamp(6) without time zone NOT NULL,
    hostname character varying
);


--
-- Name: deployments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deployments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deployments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deployments_id_seq OWNED BY public.deployments.id;


--
-- Name: error_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_groups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    fingerprint character varying NOT NULL,
    error_class character varying NOT NULL,
    message text,
    backtrace text[] DEFAULT '{}'::text[],
    last_tx_name character varying,
    last_uri character varying,
    total_count bigint DEFAULT 0 NOT NULL,
    first_seen_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone
);


--
-- Name: error_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_groups_id_seq OWNED BY public.error_groups.id;


--
-- Name: error_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    fingerprint character varying NOT NULL,
    tx_type character varying NOT NULL,
    tx_name character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL
);


--
-- Name: error_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_rollups_id_seq OWNED BY public.error_rollups.id;


--
-- Name: hosts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hosts (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    hostname character varying NOT NULL,
    pid integer,
    environment character varying,
    agent_version character varying,
    rails_version character varying,
    ruby_version character varying,
    payloads bigint DEFAULT 0 NOT NULL,
    bytes bigint DEFAULT 0 NOT NULL,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: hosts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hosts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hosts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hosts_id_seq OWNED BY public.hosts.id;


--
-- Name: incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incidents (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    alert_policy_id bigint NOT NULL,
    opened_at timestamp(6) without time zone NOT NULL,
    closed_at timestamp(6) without time zone,
    threshold double precision NOT NULL,
    opened_value double precision,
    peak_value double precision,
    last_value double precision,
    notify_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: incidents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.incidents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: incidents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.incidents_id_seq OWNED BY public.incidents.id;


--
-- Name: ingested_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingested_buckets (
    app_id bigint NOT NULL,
    bucket_id uuid NOT NULL,
    received_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_clients (
    id bigint NOT NULL,
    client_id character varying NOT NULL,
    name character varying NOT NULL,
    redirect_uris character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_clients_id_seq OWNED BY public.oauth_clients.id;


--
-- Name: oauth_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_codes (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    oauth_client_id bigint NOT NULL,
    code_digest character varying NOT NULL,
    redirect_uri character varying NOT NULL,
    code_challenge character varying NOT NULL,
    resource character varying,
    expires_at timestamp(6) without time zone NOT NULL,
    used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_codes_id_seq OWNED BY public.oauth_codes.id;


--
-- Name: runtime_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.runtime_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    hostname character varying NOT NULL,
    pid integer NOT NULL,
    elapsed_ms double precision DEFAULT 0.0 NOT NULL,
    cpu_ms double precision DEFAULT 0.0 NOT NULL,
    gc_time_ms double precision DEFAULT 0.0 NOT NULL,
    gc_count bigint DEFAULT 0 NOT NULL,
    gc_major bigint DEFAULT 0 NOT NULL,
    allocations bigint DEFAULT 0 NOT NULL,
    rss_mb double precision,
    heap_live_slots bigint,
    threads integer,
    db_pool_size integer,
    db_pool_busy integer,
    db_pool_waiting integer
);


--
-- Name: runtime_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.runtime_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: runtime_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.runtime_rollups_id_seq OWNED BY public.runtime_rollups.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: segment_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.segment_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    tx_type character varying NOT NULL,
    tx_name character varying NOT NULL,
    name character varying NOT NULL,
    category character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    txns bigint DEFAULT 0 NOT NULL,
    total double precision DEFAULT 0.0 NOT NULL,
    excl double precision DEFAULT 0.0 NOT NULL,
    min double precision,
    max double precision
);


--
-- Name: segment_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.segment_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: segment_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.segment_rollups_id_seq OWNED BY public.segment_rollups.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    ip_address character varying,
    user_agent character varying,
    last_seen_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: slow_queries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.slow_queries (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    key character varying NOT NULL,
    duration double precision NOT NULL,
    tx_type character varying NOT NULL,
    tx_name character varying NOT NULL,
    uri character varying,
    hostname character varying,
    location character varying,
    backtrace text[] DEFAULT '{}'::text[] NOT NULL,
    explain text
);


--
-- Name: slow_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.slow_queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: slow_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.slow_queries_id_seq OWNED BY public.slow_queries.id;


--
-- Name: sql_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sql_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    tx_type character varying NOT NULL,
    tx_name character varying NOT NULL,
    key character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    txns bigint DEFAULT 0 NOT NULL,
    total double precision DEFAULT 0.0 NOT NULL,
    min double precision,
    max double precision,
    max_per_tx integer DEFAULT 0 NOT NULL,
    hist bigint[] DEFAULT '{}'::bigint[] NOT NULL,
    slow_count bigint DEFAULT 0 NOT NULL
);


--
-- Name: sql_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sql_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sql_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sql_rollups_id_seq OWNED BY public.sql_rollups.id;


--
-- Name: sql_statements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sql_statements (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    key character varying NOT NULL,
    sql text NOT NULL,
    operation character varying,
    table_name character varying,
    location character varying,
    first_seen_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone,
    last_explain text,
    last_explain_at timestamp(6) without time zone
);


--
-- Name: sql_statements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sql_statements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sql_statements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sql_statements_id_seq OWNED BY public.sql_statements.id;


--
-- Name: sso_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sso_configs (
    id bigint NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    button_label character varying DEFAULT 'OneLogin'::character varying NOT NULL,
    idp_metadata_url character varying,
    idp_metadata_xml text,
    auto_provision boolean DEFAULT false NOT NULL,
    allowed_domains character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    password_login character varying DEFAULT 'everyone'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sso_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sso_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sso_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sso_configs_id_seq OWNED BY public.sso_configs.id;


--
-- Name: traces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.traces (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    tx_type character varying NOT NULL,
    tx_name character varying NOT NULL,
    duration double precision NOT NULL,
    uri character varying,
    status integer,
    error_class character varying,
    segment_count integer,
    hostname character varying,
    breakdown jsonb DEFAULT '{}'::jsonb NOT NULL,
    tree jsonb DEFAULT '[]'::jsonb NOT NULL,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: traces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.traces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: traces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.traces_id_seq OWNED BY public.traces.id;


--
-- Name: tx_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tx_rollups (
    id bigint NOT NULL,
    app_id bigint NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    tx_type character varying NOT NULL,
    name character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    total double precision DEFAULT 0.0 NOT NULL,
    min double precision,
    max double precision,
    sumsq double precision DEFAULT 0.0 NOT NULL,
    errors_count bigint DEFAULT 0 NOT NULL,
    apdex_s bigint DEFAULT 0 NOT NULL,
    apdex_t bigint DEFAULT 0 NOT NULL,
    apdex_f bigint DEFAULT 0 NOT NULL,
    queue_total double precision DEFAULT 0.0 NOT NULL,
    t_middleware double precision DEFAULT 0.0 NOT NULL,
    t_controller double precision DEFAULT 0.0 NOT NULL,
    t_view double precision DEFAULT 0.0 NOT NULL,
    t_activerecord double precision DEFAULT 0.0 NOT NULL,
    t_database double precision DEFAULT 0.0 NOT NULL,
    t_external double precision DEFAULT 0.0 NOT NULL,
    t_cache double precision DEFAULT 0.0 NOT NULL,
    t_custom double precision DEFAULT 0.0 NOT NULL,
    t_job double precision DEFAULT 0.0 NOT NULL,
    hist bigint[] DEFAULT '{}'::bigint[] NOT NULL,
    t_graphql double precision DEFAULT 0.0 NOT NULL
);


--
-- Name: tx_rollups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tx_rollups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tx_rollups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tx_rollups_id_seq OWNED BY public.tx_rollups.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    name character varying,
    password_digest character varying,
    role character varying DEFAULT 'member'::character varying NOT NULL,
    last_sign_in_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    last_sign_in_via character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: alert_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_policies ALTER COLUMN id SET DEFAULT nextval('public.alert_policies_id_seq'::regclass);


--
-- Name: api_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens ALTER COLUMN id SET DEFAULT nextval('public.api_tokens_id_seq'::regclass);


--
-- Name: app_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_rollups ALTER COLUMN id SET DEFAULT nextval('public.app_rollups_id_seq'::regclass);


--
-- Name: apps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps ALTER COLUMN id SET DEFAULT nextval('public.apps_id_seq'::regclass);


--
-- Name: deployments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deployments ALTER COLUMN id SET DEFAULT nextval('public.deployments_id_seq'::regclass);


--
-- Name: error_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups ALTER COLUMN id SET DEFAULT nextval('public.error_groups_id_seq'::regclass);


--
-- Name: error_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_rollups ALTER COLUMN id SET DEFAULT nextval('public.error_rollups_id_seq'::regclass);


--
-- Name: hosts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hosts ALTER COLUMN id SET DEFAULT nextval('public.hosts_id_seq'::regclass);


--
-- Name: incidents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents ALTER COLUMN id SET DEFAULT nextval('public.incidents_id_seq'::regclass);


--
-- Name: oauth_clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients ALTER COLUMN id SET DEFAULT nextval('public.oauth_clients_id_seq'::regclass);


--
-- Name: oauth_codes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_codes ALTER COLUMN id SET DEFAULT nextval('public.oauth_codes_id_seq'::regclass);


--
-- Name: runtime_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runtime_rollups ALTER COLUMN id SET DEFAULT nextval('public.runtime_rollups_id_seq'::regclass);


--
-- Name: segment_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_rollups ALTER COLUMN id SET DEFAULT nextval('public.segment_rollups_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: slow_queries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slow_queries ALTER COLUMN id SET DEFAULT nextval('public.slow_queries_id_seq'::regclass);


--
-- Name: sql_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sql_rollups ALTER COLUMN id SET DEFAULT nextval('public.sql_rollups_id_seq'::regclass);


--
-- Name: sql_statements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sql_statements ALTER COLUMN id SET DEFAULT nextval('public.sql_statements_id_seq'::regclass);


--
-- Name: sso_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sso_configs ALTER COLUMN id SET DEFAULT nextval('public.sso_configs_id_seq'::regclass);


--
-- Name: traces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.traces ALTER COLUMN id SET DEFAULT nextval('public.traces_id_seq'::regclass);


--
-- Name: tx_rollups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tx_rollups ALTER COLUMN id SET DEFAULT nextval('public.tx_rollups_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: alert_policies alert_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_policies
    ADD CONSTRAINT alert_policies_pkey PRIMARY KEY (id);


--
-- Name: api_tokens api_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_pkey PRIMARY KEY (id);


--
-- Name: app_rollups app_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_rollups
    ADD CONSTRAINT app_rollups_pkey PRIMARY KEY (id);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: deployments deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_pkey PRIMARY KEY (id);


--
-- Name: error_groups error_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_groups
    ADD CONSTRAINT error_groups_pkey PRIMARY KEY (id);


--
-- Name: error_rollups error_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_rollups
    ADD CONSTRAINT error_rollups_pkey PRIMARY KEY (id);


--
-- Name: hosts hosts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hosts
    ADD CONSTRAINT hosts_pkey PRIMARY KEY (id);


--
-- Name: incidents incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_codes oauth_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_codes
    ADD CONSTRAINT oauth_codes_pkey PRIMARY KEY (id);


--
-- Name: runtime_rollups runtime_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runtime_rollups
    ADD CONSTRAINT runtime_rollups_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: segment_rollups segment_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_rollups
    ADD CONSTRAINT segment_rollups_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: slow_queries slow_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.slow_queries
    ADD CONSTRAINT slow_queries_pkey PRIMARY KEY (id);


--
-- Name: sql_rollups sql_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sql_rollups
    ADD CONSTRAINT sql_rollups_pkey PRIMARY KEY (id);


--
-- Name: sql_statements sql_statements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sql_statements
    ADD CONSTRAINT sql_statements_pkey PRIMARY KEY (id);


--
-- Name: sso_configs sso_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sso_configs
    ADD CONSTRAINT sso_configs_pkey PRIMARY KEY (id);


--
-- Name: traces traces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.traces
    ADD CONSTRAINT traces_pkey PRIMARY KEY (id);


--
-- Name: tx_rollups tx_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tx_rollups
    ADD CONSTRAINT tx_rollups_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_error_rollups_fp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_error_rollups_fp ON public.error_rollups USING btree (app_id, fingerprint, ts);


--
-- Name: idx_error_rollups_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_error_rollups_key ON public.error_rollups USING btree (app_id, ts, fingerprint, tx_type, tx_name);


--
-- Name: idx_one_open_incident_per_policy; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_one_open_incident_per_policy ON public.incidents USING btree (alert_policy_id) WHERE (closed_at IS NULL);


--
-- Name: idx_runtime_rollups_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_runtime_rollups_key ON public.runtime_rollups USING btree (app_id, ts, hostname, pid);


--
-- Name: idx_segment_rollups_cat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_segment_rollups_cat ON public.segment_rollups USING btree (app_id, category, ts);


--
-- Name: idx_segment_rollups_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_segment_rollups_key ON public.segment_rollups USING btree (app_id, ts, tx_type, tx_name, name);


--
-- Name: idx_segment_rollups_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_segment_rollups_name ON public.segment_rollups USING btree (app_id, name, ts);


--
-- Name: idx_segment_rollups_tx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_segment_rollups_tx ON public.segment_rollups USING btree (app_id, tx_type, tx_name, ts);


--
-- Name: idx_sql_rollups_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_sql_rollups_key ON public.sql_rollups USING btree (app_id, ts, tx_type, tx_name, key);


--
-- Name: idx_sql_rollups_stmt; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sql_rollups_stmt ON public.sql_rollups USING btree (app_id, key, ts);


--
-- Name: idx_sql_rollups_tx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sql_rollups_tx ON public.sql_rollups USING btree (app_id, tx_type, tx_name, ts);


--
-- Name: idx_tx_rollups_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tx_rollups_key ON public.tx_rollups USING btree (app_id, ts, tx_type, name);


--
-- Name: idx_tx_rollups_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tx_rollups_name ON public.tx_rollups USING btree (app_id, tx_type, name, ts);


--
-- Name: index_alert_policies_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_alert_policies_on_app_id ON public.alert_policies USING btree (app_id);


--
-- Name: index_api_tokens_on_oauth_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_tokens_on_oauth_client_id ON public.api_tokens USING btree (oauth_client_id);


--
-- Name: index_api_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_tokens_on_token_digest ON public.api_tokens USING btree (token_digest);


--
-- Name: index_api_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_tokens_on_user_id ON public.api_tokens USING btree (user_id);


--
-- Name: index_app_rollups_on_app_id_and_ts_and_tx_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_app_rollups_on_app_id_and_ts_and_tx_type ON public.app_rollups USING btree (app_id, ts, tx_type);


--
-- Name: index_apps_on_api_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_apps_on_api_key ON public.apps USING btree (api_key);


--
-- Name: index_apps_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_apps_on_name ON public.apps USING btree (name);


--
-- Name: index_deployments_on_app_id_and_deployed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deployments_on_app_id_and_deployed_at ON public.deployments USING btree (app_id, deployed_at);


--
-- Name: index_deployments_on_app_id_and_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_deployments_on_app_id_and_revision ON public.deployments USING btree (app_id, revision);


--
-- Name: index_error_groups_on_app_id_and_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_groups_on_app_id_and_fingerprint ON public.error_groups USING btree (app_id, fingerprint);


--
-- Name: index_hosts_on_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_hosts_on_app_id ON public.hosts USING btree (app_id);


--
-- Name: index_hosts_on_app_id_and_hostname_and_pid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_hosts_on_app_id_and_hostname_and_pid ON public.hosts USING btree (app_id, hostname, pid);


--
-- Name: index_incidents_on_app_id_and_opened_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_incidents_on_app_id_and_opened_at ON public.incidents USING btree (app_id, opened_at);


--
-- Name: index_ingested_buckets_on_app_id_and_bucket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ingested_buckets_on_app_id_and_bucket_id ON public.ingested_buckets USING btree (app_id, bucket_id);


--
-- Name: index_ingested_buckets_on_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingested_buckets_on_received_at ON public.ingested_buckets USING btree (received_at);


--
-- Name: index_oauth_clients_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_clients_on_client_id ON public.oauth_clients USING btree (client_id);


--
-- Name: index_oauth_codes_on_code_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_codes_on_code_digest ON public.oauth_codes USING btree (code_digest);


--
-- Name: index_oauth_codes_on_oauth_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_codes_on_oauth_client_id ON public.oauth_codes USING btree (oauth_client_id);


--
-- Name: index_oauth_codes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_codes_on_user_id ON public.oauth_codes USING btree (user_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_slow_queries_on_app_id_and_key_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_slow_queries_on_app_id_and_key_and_ts ON public.slow_queries USING btree (app_id, key, ts);


--
-- Name: index_slow_queries_on_app_id_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_slow_queries_on_app_id_and_ts ON public.slow_queries USING btree (app_id, ts);


--
-- Name: index_sql_statements_on_app_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sql_statements_on_app_id_and_key ON public.sql_statements USING btree (app_id, key);


--
-- Name: index_traces_on_app_id_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_traces_on_app_id_and_ts ON public.traces USING btree (app_id, ts);


--
-- Name: index_traces_on_app_id_and_tx_type_and_tx_name_and_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_traces_on_app_id_and_tx_type_and_tx_name_and_ts ON public.traces USING btree (app_id, tx_type, tx_name, ts);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: oauth_codes fk_rails_0378c35eed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_codes
    ADD CONSTRAINT fk_rails_0378c35eed FOREIGN KEY (oauth_client_id) REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: hosts fk_rails_3d1fec7a4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hosts
    ADD CONSTRAINT fk_rails_3d1fec7a4a FOREIGN KEY (app_id) REFERENCES public.apps(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: api_tokens fk_rails_7d3d3df8bd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT fk_rails_7d3d3df8bd FOREIGN KEY (oauth_client_id) REFERENCES public.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_codes fk_rails_d4c1d7d44e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_codes
    ADD CONSTRAINT fk_rails_d4c1d7d44e FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: api_tokens fk_rails_f16b5e0447; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT fk_rails_f16b5e0447 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261124000002'),
('20261124000001'),
('20261120000001'),
('20261119000007'),
('20261119000006'),
('20261119000005'),
('20261119000004'),
('20261119000003'),
('20261119000002'),
('20261119000001');

