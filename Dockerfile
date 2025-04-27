# 第一阶段构建，使用基于 Python 3.13 的 Alpine 轻量级镜像作为基础镜像
FROM python:3.13-alpine AS builder

# 定义构建参数，指定 Nginx 版本和 RTMP 模块版本
ARG NGINX_VER=1.27.4
ARG RTMP_VER=1.2.2

# 设置工作目录为 /app
WORKDIR /app

# 将当前目录下的 Pipfile 和 Pipfile.lock 复制到工作目录
COPY Pipfile* ./

# 运行命令，更新 Alpine 软件包索引，安装编译依赖包，安装 pipenv 并使用它安装项目依赖
RUN apk update && apk add --no-cache gcc musl-dev python3-dev libffi-dev zlib-dev jpeg-dev wget make pcre-dev openssl-dev \
  && pip install pipenv \
  && PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy

# 下载并解压 Nginx 源码包
RUN wget https://nginx.org/download/nginx-${NGINX_VER}.tar.gz && \
    tar xzf nginx-${NGINX_VER}.tar.gz

# 下载并解压 Nginx RTMP 模块源码包
RUN wget https://github.com/arut/nginx-rtmp-module/archive/v${RTMP_VER}.tar.gz && \
    tar xzf v${RTMP_VER}.tar.gz

# 切换到 Nginx 源码目录
WORKDIR /app/nginx-${NGINX_VER}
# 配置、编译并安装 Nginx，同时添加 RTMP 模块
RUN ./configure \
    --add-module=/app/nginx-rtmp-module-${RTMP_VER} \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --with-http_ssl_module && \
    make && \
    make install

# 第二阶段构建，再次使用基于 Python 3.13 的 Alpine 轻量级镜像作为基础镜像
FROM python:3.13-alpine

# 定义构建参数，指定应用工作目录
ARG APP_WORKDIR=/iptv-api

# 设置环境变量，包括应用工作目录、主机地址、端口、路径和定时任务时间
ENV APP_WORKDIR=$APP_WORKDIR
ENV APP_HOST="http://localhost"
ENV APP_PORT=8000
ENV PATH="/.venv/bin:/usr/local/nginx/sbin:$PATH"
ENV UPDATE_CRON="0 22,10 * * *"

# 设置工作目录为应用工作目录
WORKDIR $APP_WORKDIR

# 将当前目录下的所有文件复制到应用工作目录
COPY . $APP_WORKDIR

# 从第一阶段构建的镜像中复制虚拟环境和 Nginx 安装目录
COPY --from=builder /app/.venv /.venv
COPY --from=builder /usr/local/nginx /usr/local/nginx

# 创建 Nginx 日志目录，并将日志文件重定向到标准输出和标准错误输出
RUN mkdir -p /var/log/nginx && \
  ln -sf /dev/stdout /var/log/nginx/access.log && \
  ln -sf /dev/stderr /var/log/nginx/error.log

# 更新 Alpine 软件包索引，安装 dcron、ffmpeg 和 pcre
RUN apk update && apk add --no-cache dcron ffmpeg pcre

# 暴露应用端口、8080 端口和 1935 端口
EXPOSE $APP_PORT 8080 1935

# 将 entrypoint.sh 脚本复制到容器中
COPY entrypoint.sh /iptv-api-entrypoint.sh

# 将 config 目录复制到容器中
COPY config /iptv-api-config

# 将 nginx.conf 配置文件复制到 Nginx 配置目录
COPY nginx.conf /etc/nginx/nginx.conf

# 创建 Nginx HTML 目录
RUN mkdir -p /usr/local/nginx/html

# 将 stat.xsl 文件复制到 Nginx HTML 目录
COPY stat.xsl /usr/local/nginx/html/stat.xsl

# 给 entrypoint.sh 脚本添加可执行权限
RUN chmod +x /iptv-api-entrypoint.sh

# 设置容器启动时执行的入口点脚本
ENTRYPOINT /iptv-api-entrypoint.sh
