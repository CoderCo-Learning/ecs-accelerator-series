# ECR & Image Promotion Strategy

## Why

Up to now, everything we’ve done has been local.

You build an image.
You run it.
You fix it instantly.

That works on a laptop.

The moment we move to ECS, the rules change:

- you don’t SSH into containers (although you can)
- you don’t patch running systems
- you don’t “fix prod live”

Instead, the image becomes the unit of deployment.

If you don’t control your images properly, everything after this becomes painful – CI/CD, ECS, rollbacks, debugging.

This session fixes that.

## Containers vs Images

A container is temporary.
It will die, restart, or be replaced.

An image is permanent.
Once built, it should never change.

In production:

- you replace containers
- you never modify images

That’s why ECS works the way it does.

## What ECR Is (And What It Isn’t)

Amazon ECR is a private Docker registry. Same as DockerHub, ACR, GCR etc. 

That’s it.

It stores images and controls:

- who can push
- who can pull
- how long images live

ECS doesn’t build images.
ECS doesn’t modify images.
ECS only pulls exactly what you tell it to.

This separation is intentional.

## The Real Problem: Knowing What’s Running

When something breaks in production, the first question is always:

- “What version is running right now?”

If the answer is:

- “latest”

You’re already in trouble.

## Why latest is dangerous

latest is not a version.
It’s a moving pointer.

That means:

- today it points to one image
- tomorrow it may point to another
- ECS may pull different code at different times

This breaks:

- traceability
- rollbacks
- confidence

Production systems must be predictable.

## Immutable Images - Build Once

In real systems:

- an image is built once
- hat same image is used everywhere
- environments differ via config, not rebuilds

If you rebuild the image per environment, you’ve already lost the ability to debug reliably.

## Tagging Strategy That Actually Works

Healthy images have two types of tags.

Immutable tags (never change)

Examples:

- git SHA
- version number

These are used for:

- auditing
- rollbacks
- debugging

### Mutable tags (intentional pointers)

Examples:

- dev
- staging
- prod

These point to immutable images and move forward on purpose.

A real image might look like this:

```bash
my-app:git-a8c91f2
my-app:1.4.0
my-app:prod
```

All tags point to the same image.

## What “Promotion” Really Means

Promotion does not mean rebuilding.

Promotion means:

- taking an existing image
- attaching a new tag
- giving it new meaning

Same image.
New responsibility.

This is how teams move safely from dev to prod.

## How ECS Uses This

ECS does exactly what you tell it.

If your task definition says:

`my-app:prod`

Then whatever prod points to is what runs. So you're not always guessing.

That’s why precision matters.

## Image Hygiene (ECR Lifecycle Policies)

ECR does not clean up images automatically.

Without lifecycle policies:

- old image versions pile up
- untagged images accumulate
- storage costs quietly increase

This is a common production foot-gun.

What lifecycle policies do

Lifecycle policies allow you to:

- expire untagged images
- keep only the last N versions
- automatically clean unused artifacts

A typical rule is:

- delete untagged images older than X
- keep the last 10–20 images per repo

This keeps repositories:

- clean
- predictable
- cost-controlled

Lifecycle policies are not optimisation.
They are basic operational discipline.
