import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {Background} from './components/Background';
import {ArchiveScene} from './scenes/ArchiveScene';
import {DatabaseScene} from './scenes/DatabaseScene';
import {EndScene} from './scenes/EndScene';
import {HookScene} from './scenes/HookScene';
import {MarkdownScene} from './scenes/MarkdownScene';
import {ModelScene} from './scenes/ModelScene';
import {NotebookScene} from './scenes/NotebookScene';
import {SecretsScene} from './scenes/SecretsScene';
import {SettingsScene} from './scenes/SettingsScene';
import {sceneDurations, sceneStart, type SceneId} from './theme/timing';

const scenes: {id: SceneId; Component: React.FC}[] = [
  {id: 'hook', Component: HookScene},
  {id: 'secrets', Component: SecretsScene},
  {id: 'database', Component: DatabaseScene},
  {id: 'archive', Component: ArchiveScene},
  {id: 'notebook', Component: NotebookScene},
  {id: 'markdown', Component: MarkdownScene},
  {id: 'model', Component: ModelScene},
  {id: 'settings', Component: SettingsScene},
  {id: 'end', Component: EndScene},
];

export const Preview: React.FC = () => (
  <AbsoluteFill style={{background: '#07081a', overflow: 'hidden'}}>
    <Background />
    {scenes.map(({id, Component}) => (
      <Sequence key={id} from={sceneStart(id)} durationInFrames={sceneDurations[id]} name={id}>
        <Component />
      </Sequence>
    ))}
  </AbsoluteFill>
);
