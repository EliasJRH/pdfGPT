# Download LFS content while building in order to make this step cacheable
#===== LFS =====
# FROM alpine/git:2.36.2 AS lfs
# WORKDIR /app
# COPY --link .lfs.hf.co .
# RUN --mount=type=secret,id=SPACE_REPOSITORY,mode=0444,required=true \
# 	git init \
# 	&& git remote add origin $(cat /run/secrets/SPACE_REPOSITORY) \
# 	&& git add --all \
# 	&& git config user.email "name@mail.com" \
# 	&& git config user.name "Name" \
# 	&& git commit -m "lfs" \
# 	&& git lfs pull \
# 	&& rm -rf .git .gitattributes
#===============

FROM python:3.10 as base
ENV DEBIAN_FRONTEND=noninteractive \
	TZ=Europe/Paris

# BEGIN Static Part
RUN apt-get update && apt-get install -y \
	git \
	git-lfs \
	ffmpeg \
	libsm6 \
	libxext6 \
	cmake \
	libgl1-mesa-glx \
	&& rm -rf /var/lib/apt/lists/* \
	&& git lfs install

# User
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
	PATH=/home/user/.local/bin:$PATH
WORKDIR /home/user/app

RUN pip install --no-cache-dir pip==22.3.1 && \
	pip install --no-cache-dir \
	datasets \
	"huggingface-hub>=0.19" "hf-transfer>=0.1.4" "protobuf<4" "click<8.1" "pydantic~=1.0"

#^ Waiting for https://github.com/huggingface/huggingface_hub/pull/1345/files to be merge

# END Static Part

# BEGIN Dynamic Part
USER root
# User Debian packages
## Security warning : Potential user code executed as root (build time)
RUN --mount=target=/root/packages.txt,source=packages.txt \
	apt-get update && \
	xargs -r -a /root/packages.txt apt-get install -y \
	&& rm -rf /var/lib/apt/lists/*

USER user

# Pre requirements (e.g. upgrading pip)
RUN --mount=target=pre-requirements.txt,source=pre-requirements.txt \
	pip install --no-cache-dir -r pre-requirements.txt

# Python packages
RUN --mount=target=requirements.txt,source=requirements.txt \
	pip install --no-cache-dir -r requirements.txt

# Streamlit and Gradio
RUN pip install --no-cache-dir \
	gradio[oauth]==3.20.1 \
	"uvicorn>=0.14.0" \
	spaces==0.18.0 

FROM base as pipfreeze
RUN pip freeze > /tmp/freeze.txt
FROM base

# COPY --link --chown=1000 --from=lfs /app /home/user/app
COPY --link --chown=1000 ./ /home/user/app
# Warning, if you change something under this line, dont forget to change the PIP_FREEZE_REVERSED_INDEX
COPY --from=pipfreeze --link --chown=1000 /tmp/freeze.txt .
ENV PYTHONPATH=$HOME/app \
	PYTHONUNBUFFERED=1 \
	HF_HUB_ENABLE_HF_TRANSFER=1 \
	GRADIO_ALLOW_FLAGGING=never \
	GRADIO_NUM_PORTS=1 \
	GRADIO_SERVER_NAME=0.0.0.0 \
	GRADIO_THEME=huggingface \
	TQDM_POSITION=-1 \
	TQDM_MININTERVAL=1 \
	SYSTEM=spaces

