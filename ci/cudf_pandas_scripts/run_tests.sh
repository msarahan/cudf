#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2023-2024, NVIDIA CORPORATION & AFFILIATES.
# All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -eoxu pipefail

RAPIDS_TESTS_DIR=${RAPIDS_TESTS_DIR:-"${PWD}/test-results"}
RAPIDS_COVERAGE_DIR=${RAPIDS_COVERAGE_DIR:-"${PWD}/coverage-results"}
mkdir -p "${RAPIDS_TESTS_DIR}" "${RAPIDS_COVERAGE_DIR}"

# Function to display script usage
function display_usage {
    echo "Usage: $0 [--no-cudf]"
}

# Default value for the --no-cudf option
no_cudf=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cudf)
            no_cudf=true
            shift
            ;;
        *)
            echo "Error: Unknown option $1"
            display_usage
            exit 1
            ;;
    esac
done

if [ "$no_cudf" = true ]; then
    echo "Skipping cudf install"
else
    RAPIDS_PY_CUDA_SUFFIX="$(rapids-wheel-ctk-name-gen ${RAPIDS_CUDA_VERSION})"
    RAPIDS_PY_WHEEL_NAME="libcudf_${RAPIDS_PY_CUDA_SUFFIX}" rapids-download-wheels-from-s3 cpp ./local-cudf-dep
    RAPIDS_PY_WHEEL_NAME="cudf_${RAPIDS_PY_CUDA_SUFFIX}" rapids-download-wheels-from-s3 python ./local-cudf-dep

    # --- start of section to remove ---#
    # TODO: remove this before merging
    # use librmm and rmm from https://github.com/rapidsai/rmm/pull/1644
    RAPIDS_REPOSITORY=rmm \
    RAPIDS_BUILD_TYPE=pull-request \
    RAPIDS_REF_NAME=1644 \
    RAPIDS_SHA=e93f26c \
    RAPIDS_PY_WHEEL_NAME="rmm_${RAPIDS_PY_CUDA_SUFFIX}" \
        rapids-download-wheels-from-s3 cpp /tmp/local-rmm-dep

    RAPIDS_REPOSITORY=rmm \
    RAPIDS_BUILD_TYPE=pull-request \
    RAPIDS_REF_NAME=1644 \
    RAPIDS_SHA=e93f26c \
    RAPIDS_PY_WHEEL_NAME="rmm_${RAPIDS_PY_CUDA_SUFFIX}" \
        rapids-download-wheels-from-s3 python /tmp/local-rmm-dep

    echo "librmm-${RAPIDS_PY_CUDA_SUFFIX} @ file://$(echo /tmp/local-rmm-dep/librmm_*.whl)" >> /tmp/constraints.txt
    echo "rmm-${RAPIDS_PY_CUDA_SUFFIX} @ file://$(echo /tmp/local-rmm-dep/rmm_*.whl)" >> /tmp/constraints.txt

    export PIP_CONSTRAINT=/tmp/constraints.txt
    # --- end of section to remove ---#

    python -m pip install "$(echo ./local-cudf-dep/libcudf_${RAPIDS_PY_CUDA_SUFFIX}*.whl)"
    python -m pip install --find-links $(pwd)/local-cudf-dep "$(echo ./local-cudf-dep/cudf_${RAPIDS_PY_CUDA_SUFFIX}*.whl)[test,cudf-pandas-tests]"
fi

python -m pytest -p cudf.pandas \
    --cov-config=./python/cudf/.coveragerc \
    --cov=cudf \
    --cov-report=xml:"${RAPIDS_COVERAGE_DIR}/cudf-pandas-coverage.xml" \
    --cov-report=term \
    ./python/cudf/cudf_pandas_tests/
