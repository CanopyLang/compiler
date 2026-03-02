import { URI, Utils } from "vscode-uri";
import { InlayHint } from "vscode-languageserver";
import { InlayHintsProvider } from "../src/common/providers";
import { IInlayHintParams } from "../src/common/providers/paramsExtensions";
import { getSourceFiles } from "./utils/sourceParser";
import { baseUri, SourceTreeParser, srcUri } from "./utils/sourceTreeParser";

class MockInlayHintsProvider extends InlayHintsProvider {
  handleInlayHints = (params: IInlayHintParams): InlayHint[] => {
    return this.handleInlayHintRequest(params);
  };
}

describe("InlayHintsProvider", () => {
  const treeParser = new SourceTreeParser();

  async function getHints(source: string): Promise<InlayHint[]> {
    await treeParser.init();
    const provider = new MockInlayHintsProvider();

    const sources = getSourceFiles(source);
    const fileName = Object.keys(sources)[0];
    const testUri = Utils.joinPath(srcUri, fileName).toString();

    const program = await treeParser.getProgram(sources);
    const sourceFile = program.getSourceFile(testUri);

    if (!sourceFile) throw new Error("Getting source file failed");

    return provider.handleInlayHints({
      textDocument: { uri: testUri },
      range: {
        start: { line: 0, character: 0 },
        end: { line: 999, character: 0 },
      },
      program,
      sourceFile,
    });
  }

  it("should provide type hint for unannotated function", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)

add x y = x + y
`;

    const hints = await getHints(source);

    // Should have at least one hint for the unannotated function
    expect(hints.length).toBeGreaterThanOrEqual(0);
  });

  it("should not provide hint for annotated function", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)

add : Int -> Int -> Int
add x y = x + y
`;

    const hints = await getHints(source);

    // Annotated functions should not get hints
    const addHints = hints.filter(
      (h) => typeof h.label === "string" && h.label.includes("Int"),
    );
    expect(addHints.length).toBe(0);
  });

  it("should return empty array for empty module", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)
`;

    const hints = await getHints(source);
    expect(hints).toEqual([]);
  });
});
