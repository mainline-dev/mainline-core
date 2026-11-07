.PHONY: up down down-v restart logs shell test build clean \
        db-up db-down db-bounce test-db-up test-db-down test-db-bounce

up:
	docker-compose up --build

down:
	docker-compose down

down-v:
	docker-compose down -v

restart:
	docker-compose restart app

logs:
	docker-compose logs -f app

shell:
	docker-compose exec app bash
