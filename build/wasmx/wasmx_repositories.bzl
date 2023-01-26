"""A module defining the third party dependency WasmX"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

_WASMX_RUNTIME_LIB_FILEGROUP = """
filegroup(
    name = "include",
    srcs = glob(["include/**"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["lib/**"]),
    visibility = ["//visibility:public"]
)
"""

def wasmx_repositories():
    ngx_wasm_module_branch = KONG_VAR["NGX_WASM_MODULE_BRANCH"]
    wasmtime_version = KONG_VAR["WASMTIME_VERSION"]
    wasmer_version = KONG_VAR["WASMER_VERSION"]
    v8_version = KONG_VAR["V8_VERSION"]

    maybe(
        new_git_repository,
        name = "ngx_wasm_module",
        branch = ngx_wasm_module_branch,
        remote = "git@github.com:Kong/ngx_wasm_module.git",
        build_file_content = """
filegroup(
    name = "all_srcs",
    srcs = glob(["src/**"]),
    visibility = ["//visibility:public"]
)
"""
    )

    maybe(
        http_archive,
        name = "v8",
        urls = [
            "https://github.com/Kong/ngx_wasm_runtimes/releases/download/latest/ngx_wasm_runtime-v8-" + v8_version + "-linux-x86_64.tar.gz",
        ],
        strip_prefix = "v8-" + v8_version + "-linux-x86_64",
        build_file_content = _WASMX_RUNTIME_LIB_FILEGROUP,
    )

    maybe(
        http_archive,
        name = "wasmer-x86_64",
        urls = [
            "https://github.com/wasmerio/wasmer/releases/download/v" + wasmer_version + "/wasmer-linux-amd64.tar.gz",
        ],
        build_file_content = _WASMX_RUNTIME_LIB_FILEGROUP,
    )

    maybe(
        http_archive,
        name = "wasmer-arm64",
        urls = [
            "https://github.com/wasmerio/wasmer/releases/download/v" + wasmer_version + "/wasmer-linux-aarch64.tar.gz"
        ],
        build_file_content = _WASMX_RUNTIME_LIB_FILEGROUP,
    )

    maybe(
        http_archive,
        name = "wasmtime-x86_64",
        urls = [
            "https://github.com/bytecodealliance/wasmtime/releases/download/v" + wasmtime_version + "/wasmtime-v" + wasmtime_version + "-x86_64-linux-c-api.tar.xz",
        ],
        strip_prefix = "wasmtime-v" + wasmtime_version + "-x86_64-linux-c-api",
        build_file_content = _WASMX_RUNTIME_LIB_FILEGROUP,
    )

    maybe(
        http_archive,
        name = "wasmtime-arm64",
        urls = [
            "https://github.com/bytecodealliance/wasmtime/releases/download/v" + wasmtime_version + "/wasmtime-v" + wasmtime_version + "-aarch64-linux-c-api.tar.xz"
        ],
        strip_prefix = "wasmtime-v" + wasmtime_version + "-aarch64-linux-c-api",
        build_file_content = _WASMX_RUNTIME_LIB_FILEGROUP,
    )
