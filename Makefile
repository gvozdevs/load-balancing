.PHONY: all deploy clean test-iptables test-envoy test-nginx stats

ECHO_POD_LABEL=app=echo
CURL_IMAGE=radial/busyboxplus:curl
REQUEST_COUNT=20000
PARALLEL_JOBS=5
TIMEOUT_SECONDS=240


all: deploy

deploy:
	kubectl apply -f echo-server.yaml
	kubectl apply -f envoy-deployment.yaml
	kubectl apply -f nginx-deployment.yaml
	kubectl apply -f haproxy-deployment.yaml
	@echo "Deployment completed."

clean:
	kubectl delete -f echo-server.yaml --ignore-not-found
	kubectl delete -f envoy-deployment.yaml --ignore-not-found
	kubectl delete -f nginx-deployment.yaml --ignore-not-found
	kubectl delete -f haproxy-deployment.yaml --ignore-not-found
	@echo "Resources deleted."

test-all:
	@$(MAKE) test-iptables
	@$(MAKE) test-envoy
	@$(MAKE) test-nginx
	@$(MAKE) test-haproxy
	@$(MAKE) compare

test-iptables:
	@echo "Testing via iptables (kube-proxy)..."
	@kubectl delete pod curl-iptables --ignore-not-found
	@kubectl run curl-iptables --image=curlimages/curl:latest --restart=Never --command -- \
		sh -c "seq 1 $(REQUEST_COUNT) | xargs -n 1 -P $(PARALLEL_JOBS) -I {} sh -c 'curl -s -D - http://echo-service/ | grep \"^X-Pod-Name:\" || echo \"No X-Pod-Name header found in request {}\"'"
	@echo "Waiting for pod to complete..."
	@timeout=0; \
	while [ "$$(kubectl get pod curl-iptables -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ] && [ $$timeout -lt $(TIMEOUT_SECONDS) ]; do \
		echo "  Still running... ($$timeout/$(TIMEOUT_SECONDS)s)"; sleep 5; timeout=$$((timeout + 5)); \
	done
	@if [ "$$(kubectl get pod curl-iptables -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ]; then \
		echo "Pod timed out or failed. Checking status..."; \
		kubectl get pod curl-iptables; \
		kubectl logs curl-iptables 2>/dev/null || echo "No logs available"; \
		kubectl delete pod curl-iptables --wait=false; \
		exit 1; \
	fi
	@sleep 2
	@kubectl logs curl-iptables > output_iptables.txt
	@kubectl delete pod curl-iptables --wait=true
	@$(MAKE) stats FILE=output_iptables.txt

test-envoy:
	@echo "Testing via Envoy..."
	@kubectl delete pod curl-envoy --ignore-not-found
	@kubectl run curl-envoy --image=curlimages/curl:latest --restart=Never --command -- \
		sh -c "seq 1 $(REQUEST_COUNT) | xargs -n 1 -P $(PARALLEL_JOBS) -I {} sh -c 'curl -s -D - http://envoy-service/ | grep \"^x-pod-name:\" || echo \"No X-Pod-Name header found in request {}\"'"
	@echo "Waiting for pod to complete..."
	@timeout=0; \
	while [ "$$(kubectl get pod curl-envoy -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ] && [ $$timeout -lt $(TIMEOUT_SECONDS) ]; do \
		echo "  Still running... ($$timeout/$(TIMEOUT_SECONDS)s)"; sleep 5; timeout=$$((timeout + 5)); \
	done
	@if [ "$$(kubectl get pod curl-envoy -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ]; then \
		echo "Pod timed out or failed. Checking status..."; \
		kubectl get pod curl-envoy; \
		kubectl logs curl-envoy 2>/dev/null || echo "No logs available"; \
		kubectl delete pod curl-envoy --wait=false; \
		exit 1; \
	fi
	@sleep 2
	@kubectl logs curl-envoy > output_envoy.txt
	@kubectl delete pod curl-envoy --wait=true
	@$(MAKE) stats FILE=output_envoy.txt

test-nginx:
	@echo "Testing via Nginx..."
	@kubectl delete pod curl-nginx --ignore-not-found
	@kubectl run curl-nginx --image=curlimages/curl:latest --restart=Never --command -- \
		sh -c "seq 1 $(REQUEST_COUNT) | xargs -n 1 -P $(PARALLEL_JOBS) -I {} sh -c 'curl -s -D - http://nginx-service/ | grep \"^X-Pod-Name:\" || echo \"No X-Pod-Name header found in request {}\"'"
	@echo "Waiting for pod to complete..."
	@timeout=0; \
	while [ "$$(kubectl get pod curl-nginx -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ] && [ $$timeout -lt $(TIMEOUT_SECONDS) ]; do \
		echo "  Still running... ($$timeout/$(TIMEOUT_SECONDS)s)"; sleep 5; timeout=$$((timeout + 5)); \
	done
	@if [ "$$(kubectl get pod curl-nginx -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ]; then \
		echo "Pod timed out or failed. Checking status..."; \
		kubectl get pod curl-nginx; \
		kubectl logs curl-nginx 2>/dev/null || echo "No logs available"; \
		kubectl delete pod curl-nginx --wait=false; \
		exit 1; \
	fi
	@sleep 2
	@kubectl logs curl-nginx > output_nginx.txt
	@kubectl delete pod curl-nginx --wait=true
	@$(MAKE) stats FILE=output_nginx.txt

test-haproxy:
	@echo "Testing via HAProxy..."
	@kubectl delete pod curl-haproxy --ignore-not-found
	@kubectl run curl-haproxy --image=curlimages/curl:latest --restart=Never --command -- \
		sh -c "seq 1 $(REQUEST_COUNT) | xargs -n 1 -P $(PARALLEL_JOBS) -I {} sh -c 'curl -s -D - http://haproxy-service/ | grep \"^x-pod-name:\" || echo \"No X-Pod-Name header found in request {}\"'"
	@echo "Waiting for pod to complete..."
	@timeout=0; \
	while [ "$$(kubectl get pod curl-haproxy -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ] && [ $$timeout -lt $(TIMEOUT_SECONDS) ]; do \
		echo "  Still running... ($$timeout/$(TIMEOUT_SECONDS)s)"; sleep 5; timeout=$$((timeout + 5)); \
	done
	@if [ "$$(kubectl get pod curl-haproxy -o jsonpath='{.status.phase}' 2>/dev/null)" != "Succeeded" ]; then \
		echo "Pod timed out or failed. Checking status..."; \
		kubectl get pod curl-haproxy; \
		kubectl logs curl-haproxy 2>/dev/null || echo "No logs available"; \
		kubectl delete pod curl-haproxy --wait=false; \
		exit 1; \
	fi
	@sleep 2
	@kubectl logs curl-haproxy > output_haproxy.txt
	@kubectl delete pod curl-haproxy --wait=true
	@$(MAKE) stats FILE=output_haproxy.txt

stats-iptables:
	$(MAKE) stats FILE=$(PWD)/output_iptables.txt

stats:
	@echo "=== Response Stats from $(FILE) ==="
	@if [ -f "$(FILE)" ] && [ -s "$(FILE)" ]; then \
		if grep -q '^X-Pod-Name:' $(FILE); then \
			grep -o 'X-Pod-Name: .*' $(FILE) \
				| sed 's/^X-Pod-Name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %2d  %s\n", $$1, $$2}'; \
		elif grep -q '^x-pod-name:' $(FILE); then \
			grep -o 'x-pod-name: .*' $(FILE) \
				| sed 's/^x-pod-name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %2d  %s\n", $$1, $$2}'; \
		else \
			echo "  No X-Pod-Name or x-pod-name headers found in $(FILE)"; \
		fi; \
	else \
		echo "  File $(FILE) is empty or does not exist"; \
		echo "  Checking pod logs for errors..."; \
	fi

compare:
	@echo "=========================================="
	@echo "=== СРАВНЕНИЕ РЕЗУЛЬТАТОВ ТЕСТОВ ==="
	@echo "=========================================="
	@echo ""
	@echo "--- IPTABLES (kube-proxy) ---"
	@if [ -f "output_iptables.txt" ] && [ -s "output_iptables.txt" ]; then \
		if grep -q '^X-Pod-Name:' output_iptables.txt; then \
			grep -o 'X-Pod-Name: .*' output_iptables.txt \
				| sed 's/^X-Pod-Name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %3d  %s (%.1f%%)\n", $$1, $$2, ($$1/$(REQUEST_COUNT)*100)}'; \
		else \
			echo "  Данные не найдены"; \
		fi; \
	else \
		echo "  Файл output_iptables.txt не найден или пуст"; \
	fi
	@echo ""
	@echo "--- ENVOY ---"
	@if [ -f "output_envoy.txt" ] && [ -s "output_envoy.txt" ]; then \
		if grep -q '^x-pod-name:' output_envoy.txt; then \
			grep -o 'x-pod-name: .*' output_envoy.txt \
				| sed 's/^x-pod-name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %3d  %s (%.1f%%)\n", $$1, $$2, ($$1/$(REQUEST_COUNT)*100)}'; \
		else \
			echo "  Данные не найдены"; \
		fi; \
	else \
		echo "  Файл output_envoy.txt не найден или пуст"; \
	fi
	@echo ""
	@echo "--- NGINX ---"
	@if [ -f "output_nginx.txt" ] && [ -s "output_nginx.txt" ]; then \
		if grep -q '^X-Pod-Name:' output_nginx.txt; then \
			grep -o 'X-Pod-Name: .*' output_nginx.txt \
				| sed 's/^X-Pod-Name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %3d  %s (%.1f%%)\n", $$1, $$2, ($$1/$(REQUEST_COUNT)*100)}'; \
		else \
			echo "  Данные не найдены"; \
		fi; \
	else \
		echo "  Файл output_nginx.txt не найден или пуст"; \
	fi
	@echo ""
	@echo "--- HAProxy ---"
	@if [ -f "output_haproxy.txt" ] && [ -s "output_haproxy.txt" ]; then \
		if grep -q '^x-pod-name:' output_haproxy.txt; then \
			grep -o 'x-pod-name: .*' output_haproxy.txt \
				| sed 's/^x-pod-name: //' \
				| tr -d '\r' \
				| sort \
				| uniq -c \
				| sort -nr \
				| awk '{printf "  %3d  %s (%.1f%%)\n", $$1, $$2, ($$1/$(REQUEST_COUNT)*100)}'; \
		else \
			echo "  Данные не найдены"; \
		fi; \
	else \
		echo "  Файл output_haproxy.txt не найден или пуст"; \
	fi
	@echo ""
	@echo "=========================================="
	@echo "=== АНАЛИЗ РАСПРЕДЕЛЕНИЯ НАГРУЗКИ ==="
	@echo "=========================================="
	@echo ""
	@echo "Параллельность $(PARALLEL_JOBS)"
	@echo "Оценка равномерности распределения:"
	@for method in iptables envoy nginx haproxy; do \
		echo "--- $$method ---"; \
		file="output_$$method.txt"; \
		if [ -f "$$file" ] && [ -s "$$file" ]; then \
			if [ "$$method" = "envoy" ] || [ "$$method" = "haproxy" ]; then \
				header_pattern='^x-pod-name:'; \
				sed_pattern='s/^x-pod-name: //'; \
			else \
				header_pattern='^X-Pod-Name:'; \
				sed_pattern='s/^X-Pod-Name: //'; \
			fi; \
			if grep -q "$$header_pattern" "$$file"; then \
				pod_count=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq | wc -l); \
				total_requests=$$(grep -o "$$header_pattern .*" "$$file" | wc -l); \
				if [ $$pod_count -gt 0 ]; then \
					expected_per_pod=$$((total_requests / pod_count)); \
					min_requests=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq -c | sort -n | head -1 | awk '{print $$1}'); \
					max_requests=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq -c | sort -nr | head -1 | awk '{print $$1}'); \
					range_diff=$$((max_requests - min_requests)); \
					range_percent=$$((range_diff * 100 / expected_per_pod)); \
					echo "  Подов: $$pod_count"; \
					echo "  Запросов: $$total_requests"; \
					echo "  Ожидаемо на под: $$expected_per_pod"; \
					echo "  Мин/Макс запросов: $$min_requests / $$max_requests"; \
					echo "  Разброс: $$range_diff ($$range_percent%)"; \
					if [ $$range_percent -le 15 ]; then \
						echo "  Оценка: ОТЛИЧНО (разброс ≤15%)"; \
					elif [ $$range_percent -le 30 ]; then \
						echo "  Оценка: ХОРОШО (разброс ≤30%)"; \
					elif [ $$range_percent -le 50 ]; then \
						echo "  Оценка: УДОВЛЕТВОРИТЕЛЬНО (разброс ≤50%)"; \
					else \
						echo "  Оценка: ПЛОХО (разброс >50%)"; \
					fi; \
				else \
					echo "  Подов не найдено"; \
				fi; \
			else \
				echo "  Заголовки с именами подов не найдены"; \
			fi; \
		else \
			echo "  Файл не найден или пуст"; \
		fi; \
		echo ""; \
	done
