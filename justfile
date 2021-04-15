project := "tfc-agent-notifications"

image_repo := "registry.hub.docker.com"
image_tag  := "latest"

project_image_name   := image_repo + "/" + project + ":" + image_tag

build:
  docker build \
    --tag="{{project_image_name}}" \
    --file=Dockerfile \
    --progress=plain \
    .


push: build
  docker push {{project_image_name}}

run: push
  nomad job run {{project}}.nomad


shell:
  docker run -it --rm --entrypoint='' "{{project_image_name}}" bash
