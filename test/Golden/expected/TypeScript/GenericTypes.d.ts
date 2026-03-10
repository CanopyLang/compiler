export type Pair<A> = { readonly first: A; readonly second: A };

export type Either<E, A> = { readonly $: 'Left'; readonly a: E } | { readonly $: 'Right'; readonly a: A };

