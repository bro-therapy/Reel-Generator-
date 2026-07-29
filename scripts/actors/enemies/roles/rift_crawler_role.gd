class_name RiftCrawlerRole
extends EnemyBehavior

## Chaser (guide §10). Low profile, quick, short red slash telegraph. Exists to
## apply pressure rather than damage spikes, so it uses the shortest windup of
## any role and the default seek-and-strike loop.

func role_name() -> String:
	return "chaser"
