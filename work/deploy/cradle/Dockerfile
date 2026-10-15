# LiveRelay 摇篮服务 —— 只读巡检客户卷的报平安记录并发送提醒/取件邮件
FROM python:3.12-slim

WORKDIR /app
COPY cradle.py /app/cradle.py

ENV PYTHONUNBUFFERED=1 \
    TZ=Asia/Shanghai

CMD ["python3", "/app/cradle.py"]
