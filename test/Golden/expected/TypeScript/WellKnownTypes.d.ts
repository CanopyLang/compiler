export const names: ReadonlyArray<string>;

export const lookup: (p0: string) => { readonly $: 'Just'; readonly a: number } | { readonly $: 'Nothing' };

export const parse: (p0: string) => { readonly $: 'Ok'; readonly a: number } | { readonly $: 'Err'; readonly a: string };

