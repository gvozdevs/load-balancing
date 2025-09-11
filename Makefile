REQUEST_COUNT=500
POD_COUNT=90

deploy:
	kubectl apply -f echo-service.yaml
	kubectl apply -f python-load-tester.yaml
	kubectl apply -f python-load-tester-envoy.yaml
	kubectl apply -f python-load-tester-haproxy.yaml
	kubectl apply -f python-load-tester-nginx.yaml
	kubectl apply -f envoy-deployment.yaml
	kubectl apply -f nginx-deployment.yaml
	kubectl apply -f haproxy-deployment.yaml
	@echo "Deployment completed."

clean:
	kubectl delete -f echo-service.yaml --ignore-not-found
	kubectl delete -f python-load-tester.yaml --ignore-not-found
	kubectl delete -f python-load-tester-envoy.yaml --ignore-not-found
	kubectl delete -f python-load-tester-haproxy.yaml --ignore-not-found
	kubectl delete -f python-load-tester-nginx.yaml --ignore-not-found
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
	@echo "Testing via iptables..."
	@kubectl exec -it deployment/python-load-tester -- python3 /app/load_test.py > output_iptables.txt 2>&1

test-envoy:
	@echo "Testing via envoy..."
	@kubectl exec -it deployment/python-load-tester-envoy -- python3 /app/load_test.py > output_envoy.txt 2>&1

test-haproxy:
	@echo "Testing via haproxy..."
	@kubectl exec -it deployment/python-load-tester-haproxy -- python3 /app/load_test.py > output_haproxy.txt 2>&1

test-nginx:
	@echo "Testing via nginx..."
	@kubectl exec -it deployment/python-load-tester-nginx -- python3 /app/load_test.py > output_nginx.txt 2>&1

compare:
	@echo "=========================================="
	@echo "=== СРАВНЕНИЕ РЕЗУЛЬТАТОВ ТЕСТОВ ==="
	@echo "=========================================="
	@echo ""
	@echo "--- IPTABLES ---"
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
		if grep -q '^X-Pod-Name:' output_envoy.txt; then \
			grep -o 'X-Pod-Name: .*' output_envoy.txt \
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
		if grep -q '^X-Pod-Name:' output_haproxy.txt; then \
			grep -o 'X-Pod-Name: .*' output_haproxy.txt \
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
		echo "  Файл output_haproxy.txt не найден или пуст"; \
	fi
	@echo ""
	@echo "=========================================="
	@echo "=== АНАЛИЗ РАСПРЕДЕЛЕНИЯ НАГРУЗКИ ==="
	@echo "=========================================="
	@echo ""
	@echo "Оценка равномерности распределения:"
	@for method in iptables envoy nginx haproxy; do \
		echo "--- $$method ---"; \
		file="output_$$method.txt"; \
		if [ -f "$$file" ] && [ -s "$$file" ]; then \
			header_pattern='^X-Pod-Name:'; \
			sed_pattern='s/^X-Pod-Name: //'; \
			if grep -q "$$header_pattern" "$$file"; then \
				pod_count=$(POD_COUNT); \
				pod_using=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq | wc -l); \
				total_requests=$$(grep -o "$$header_pattern .*" "$$file" | wc -l); \
				if [ $$pod_count -gt 0 ]; then \
					expected_per_pod=$$((total_requests / pod_count)); \
					min_requests=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq -c | sort -n | head -1 | awk '{print $$1}'); \
					max_requests=$$(grep -o "$$header_pattern .*" "$$file" | sed "$$sed_pattern" | tr -d '\r' | sort | uniq -c | sort -nr | head -1 | awk '{print $$1}'); \
					range_diff=$$((max_requests - min_requests)); \
					range_percent=$$((range_diff * 100 / expected_per_pod)); \
					echo "  Подов: $$pod_count / $$pod_using"; \
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
